import Darwin
import Foundation

final class EchoServer {
    let port: UInt16

    private let fd: Int32
    private let queue = DispatchQueue(label: "okforward.tests.echo")
    private let lock = NSLock()
    private var isRunning = true

    init() throws {
        fd = try TestSocket.makeLoopbackServer(port: 0)
        port = try TestSocket.boundPort(fd)

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()

        TestSocket.close(fd)
    }

    private func acceptLoop() {
        while running {
            let client = accept(fd, nil, nil)

            if client < 0 {
                if errno == EINTR {
                    continue
                }
                break
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.echo(client)
            }
        }
    }

    private func echo(_ client: Int32) {
        defer {
            TestSocket.close(client)
        }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        while running {
            let received = read(client, buffer, bufferSize)

            if received > 0 {
                guard TestSocket.writeAll(client, buffer: buffer, count: received) else {
                    return
                }
                continue
            }

            if received == 0 || errno != EINTR {
                return
            }
        }
    }

    private var running: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return isRunning
    }
}

enum TestSocket {
    static func reserveLoopbackPort() throws -> UInt16 {
        let fd = try makeLoopbackServer(port: 0)
        defer {
            close(fd)
        }
        return try boundPort(fd)
    }

    static func makeLoopbackServer(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw TestSocketError.posix("socket", errno)
        }

        do {
            setOptions(fd)

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            address.sin_port = port.bigEndian

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            guard bindResult == 0 else {
                throw TestSocketError.posix("bind", errno)
            }

            guard listen(fd, 16) == 0 else {
                throw TestSocketError.posix("listen", errno)
            }

            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    static func boundPort(_ fd: Int32) throws -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }

        guard result == 0 else {
            throw TestSocketError.posix("getsockname", errno)
        }

        return UInt16(bigEndian: address.sin_port)
    }

    static func sendAndReceive(_ payload: Data, host: String, port: UInt16) throws -> Data {
        let fd = try connect(host: host, port: port)
        defer {
            close(fd)
        }

        try payload.withUnsafeBytes { rawBuffer in
            guard
                let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                writeAll(fd, buffer: baseAddress, count: payload.count)
            else {
                throw TestSocketError.message("Failed to write payload")
            }
        }

        var received = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while received.count < payload.count {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                read(fd, rawBuffer.baseAddress, bufferSize)
            }

            if count > 0 {
                received.append(contentsOf: buffer.prefix(count))
                continue
            }

            if count == 0 || errno != EINTR {
                break
            }
        }

        return received
    }

    static func connect(host: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
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
            throw TestSocketError.message("Address lookup failed: \(String(cString: gai_strerror(status)))")
        }

        defer {
            freeaddrinfo(first)
        }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var lastError: Error?

        while let current = cursor {
            let fd = socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            guard fd >= 0 else {
                lastError = TestSocketError.posix("socket", errno)
                cursor = current.pointee.ai_next
                continue
            }

            setOptions(fd)

            if Darwin.connect(fd, current.pointee.ai_addr, current.pointee.ai_addrlen) == 0 {
                return fd
            }

            lastError = TestSocketError.posix("connect", errno)
            close(fd)
            cursor = current.pointee.ai_next
        }

        throw lastError ?? TestSocketError.message("Unable to connect to \(host):\(port)")
    }

    static func writeAll(_ fd: Int32, buffer: UnsafePointer<UInt8>, count: Int) -> Bool {
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

    static func close(_ fd: Int32) {
        guard fd >= 0 else {
            return
        }

        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }

    private static func setOptions(_ fd: Int32) {
        var value: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
    }
}

enum TestSocketError: LocalizedError {
    case posix(String, Int32)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .posix(let operation, let code):
            return "\(operation) failed: \(String(cString: strerror(code)))"
        case .message(let message):
            return message
        }
    }
}
