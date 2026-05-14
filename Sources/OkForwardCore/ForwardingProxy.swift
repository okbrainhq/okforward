import Darwin
import Foundation

public enum ProxyState: Equatable {
    case stopped
    case starting
    case ready
    case failed(String)

    public var label: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case .ready:
            return "Ready"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}

public final class ForwardingProxy {
    public let rule: ProxyRule

    public var onStateChange: ((UUID, ProxyState) -> Void)?

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var listenerFD: Int32 = -1
    private var isRunning = false
    private var sessions: [UUID: ProxySession] = [:]

    public private(set) var state: ProxyState = .stopped {
        didSet {
            DispatchQueue.main.async {
                self.onStateChange?(self.rule.id, self.state)
            }
        }
    }

    public init(rule: ProxyRule) {
        self.rule = rule
        self.queue = DispatchQueue(label: "okforward.proxy.\(rule.id.uuidString)")
    }

    public func start() {
        guard rule.enabled else {
            state = .stopped
            return
        }

        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        lock.unlock()

        state = .starting

        queue.async { [weak self] in
            self?.runListener()
        }
    }

    public func stop() {
        lock.lock()
        isRunning = false
        let fd = listenerFD
        listenerFD = -1
        lock.unlock()

        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.sessions.values.forEach { $0.cancel() }
            self.sessions.removeAll()
        }

        state = .stopped
    }

    private func runListener() {
        do {
            let fd = try SocketFactory.makeServerSocket(host: rule.bindHost, port: rule.listenPort)

            lock.lock()
            listenerFD = fd
            lock.unlock()

            state = .ready
            acceptConnections(on: fd)
        } catch {
            lock.lock()
            isRunning = false
            listenerFD = -1
            lock.unlock()

            state = .failed(error.localizedDescription)
        }
    }

    private func acceptConnections(on fd: Int32) {
        while shouldRun {
            let inboundFD = accept(fd, nil, nil)

            if inboundFD >= 0 {
                setNoSigPipe(inboundFD)
                startSession(inboundFD: inboundFD)
                continue
            }

            if errno == EINTR {
                continue
            }

            if shouldRun {
                state = .failed(SocketError.posix("accept", errno).localizedDescription)
            }
            break
        }

        lock.lock()
        if listenerFD == fd {
            listenerFD = -1
        }
        isRunning = false
        lock.unlock()

        close(fd)
    }

    private var shouldRun: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return isRunning
    }

    private func startSession(inboundFD: Int32) {
        let id = UUID()
        let session = ProxySession(
            id: id,
            inboundFD: inboundFD,
            targetHost: rule.targetHost,
            targetPort: rule.targetPort
        ) { [weak self] sessionID in
            self?.queue.async {
                self?.sessions.removeValue(forKey: sessionID)
            }
        }

        sessions[id] = session
        session.start()
    }
}

private final class ProxySession {
    private let id: UUID
    private let targetHost: String
    private let targetPort: UInt16
    private let lock = NSLock()
    private let onClose: (UUID) -> Void

    private var inboundFD: Int32
    private var outboundFD: Int32 = -1
    private var isClosed = false

    init(
        id: UUID,
        inboundFD: Int32,
        targetHost: String,
        targetPort: UInt16,
        onClose: @escaping (UUID) -> Void
    ) {
        self.id = id
        self.inboundFD = inboundFD
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.onClose = onClose
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            do {
                let fd = try SocketFactory.makeClientSocket(host: self.targetHost, port: self.targetPort)

                self.lock.lock()
                if self.isClosed {
                    self.lock.unlock()
                    close(fd)
                    return
                }
                self.outboundFD = fd
                self.lock.unlock()

                self.startPumps()
            } catch {
                NSLog("Failed to connect proxy target \(self.targetHost):\(self.targetPort): \(error)")
                self.cancel()
            }
        }
    }

    func cancel() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }

        isClosed = true
        let inbound = inboundFD
        let outbound = outboundFD
        inboundFD = -1
        outboundFD = -1
        lock.unlock()

        closeIfOpen(inbound)
        closeIfOpen(outbound)
        onClose(id)
    }

    private func startPumps() {
        let inbound = inboundFD
        let outbound = outboundFD

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pump(from: inbound, to: outbound)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pump(from: outbound, to: inbound)
        }
    }

    private func pump(from sourceFD: Int32, to destinationFD: Int32) {
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        while !closed {
            let bytesRead = read(sourceFD, buffer, bufferSize)

            if bytesRead > 0 {
                guard writeAll(destinationFD, buffer: buffer, count: bytesRead) else {
                    cancel()
                    return
                }
                continue
            }

            if bytesRead == 0 || errno != EINTR {
                cancel()
                return
            }
        }
    }

    private var closed: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return isClosed
    }
}

private enum SocketFactory {
    static func makeServerSocket(host: String, port: UInt16) throws -> Int32 {
        try withAddressInfo(host: host, port: port, flags: AI_NUMERICHOST) { info in
            let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            guard fd >= 0 else {
                throw SocketError.posix("socket", errno)
            }

            do {
                setReuseAddress(fd)
                setNoSigPipe(fd)

                guard bind(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
                    throw SocketError.posix("bind", errno)
                }

                guard listen(fd, SOMAXCONN) == 0 else {
                    throw SocketError.posix("listen", errno)
                }

                return fd
            } catch {
                close(fd)
                throw error
            }
        }
    }

    static func makeClientSocket(host: String, port: UInt16) throws -> Int32 {
        try withAddressInfo(host: host, port: port, flags: 0) { info in
            let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            guard fd >= 0 else {
                throw SocketError.posix("socket", errno)
            }

            do {
                setNoSigPipe(fd)

                guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
                    throw SocketError.posix("connect", errno)
                }

                return fd
            } catch {
                close(fd)
                throw error
            }
        }
    }

    private static func withAddressInfo<T>(
        host: String,
        port: UInt16,
        flags: Int32,
        body: (UnsafeMutablePointer<addrinfo>) throws -> T
    ) throws -> T {
        var hints = addrinfo(
            ai_flags: flags,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let first = result else {
            throw SocketError.getAddrInfo(status)
        }

        defer {
            freeaddrinfo(first)
        }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var lastError: Error?

        while let current = cursor {
            do {
                return try body(current)
            } catch {
                lastError = error
                cursor = current.pointee.ai_next
            }
        }

        throw lastError ?? SocketError.message("No address found for \(host):\(port)")
    }
}

private enum SocketError: LocalizedError {
    case posix(String, Int32)
    case getAddrInfo(Int32)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .posix(let operation, let code):
            return "\(operation) failed: \(String(cString: strerror(code)))"
        case .getAddrInfo(let code):
            return "Address lookup failed: \(String(cString: gai_strerror(code)))"
        case .message(let message):
            return message
        }
    }
}

private func setReuseAddress(_ fd: Int32) {
    var value: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))
}

private func setNoSigPipe(_ fd: Int32) {
    var value: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
}

private func writeAll(_ fd: Int32, buffer: UnsafeMutablePointer<UInt8>, count: Int) -> Bool {
    var written = 0

    while written < count {
        let result = write(fd, buffer.advanced(by: written), count - written)

        if result > 0 {
            written += result
            continue
        }

        if result < 0, errno == EINTR {
            continue
        }

        return false
    }

    return true
}

private func closeIfOpen(_ fd: Int32) {
    guard fd >= 0 else {
        return
    }

    shutdown(fd, SHUT_RDWR)
    close(fd)
}
