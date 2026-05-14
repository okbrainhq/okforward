import Darwin
import Foundation
import OkForwardCore

enum ProxySmokeTest {
    static func run() -> Bool {
        do {
            let server = try EchoServer()
            defer {
                server.stop()
            }

            let listenPort = try SmokeSocket.reservePort()
            let proxy = ForwardingProxy(
                rule: ProxyRule(
                    bindHost: "127.0.0.1",
                    listenPort: listenPort,
                    targetHost: "127.0.0.1",
                    targetPort: server.port
                )
            )

            proxy.start()
            defer {
                proxy.stop()
            }

            guard waitUntilReady(proxy) else {
                fputs("Proxy did not become ready: \(proxy.state.label)\n", stderr)
                return false
            }

            let client = try SmokeSocket.connect(port: listenPort)
            defer {
                SmokeSocket.close(client)
            }

            let payload = Array("okforward-smoke".utf8)
            guard SmokeSocket.writeAll(client, bytes: payload) else {
                fputs("Failed to write smoke payload\n", stderr)
                return false
            }

            var buffer = [UInt8](repeating: 0, count: payload.count)
            let received = buffer.withUnsafeMutableBytes { rawBuffer in
                read(client, rawBuffer.baseAddress, payload.count)
            }

            guard received == payload.count else {
                fputs("Unexpected smoke response length: \(received)\n", stderr)
                return false
            }

            return Array(buffer.prefix(received)) == payload
        } catch {
            fputs("Smoke test failed: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    private static func waitUntilReady(_ proxy: ForwardingProxy) -> Bool {
        for _ in 0..<100 {
            if proxy.state == .ready {
                return true
            }

            if case .failed = proxy.state {
                return false
            }

            Thread.sleep(forTimeInterval: 0.03)
        }

        return false
    }
}

private final class EchoServer {
    let port: UInt16

    private let fd: Int32
    private let queue = DispatchQueue(label: "okforward.smoke.echo")
    private let lock = NSLock()
    private var isRunning = true

    init() throws {
        fd = try SmokeSocket.makeLoopbackServer(port: 0)
        port = try SmokeSocket.boundPort(fd)

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()

        SmokeSocket.close(fd)
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

            echo(client)
        }
    }

    private func echo(_ client: Int32) {
        defer {
            SmokeSocket.close(client)
        }

        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let received = buffer.withUnsafeMutableBytes { rawBuffer in
            read(client, rawBuffer.baseAddress, bufferSize)
        }

        guard received > 0 else {
            return
        }

        _ = buffer.withUnsafeBufferPointer { pointer in
            SmokeSocket.writeAll(client, buffer: pointer.baseAddress!, count: received)
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

private enum SmokeSocket {
    static func reservePort() throws -> UInt16 {
        let fd = try makeLoopbackServer(port: 0)
        defer {
            close(fd)
        }
        return try boundPort(fd)
    }

    static func makeLoopbackServer(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw SmokeSocketError.posix("socket", errno)
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
                throw SmokeSocketError.posix("bind", errno)
            }

            guard listen(fd, 16) == 0 else {
                throw SmokeSocketError.posix("listen", errno)
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
            throw SmokeSocketError.posix("getsockname", errno)
        }

        return UInt16(bigEndian: address.sin_port)
    }

    static func connect(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw SmokeSocketError.posix("socket", errno)
        }

        do {
            setOptions(fd)

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            address.sin_port = port.bigEndian

            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            guard result == 0 else {
                throw SmokeSocketError.posix("connect", errno)
            }

            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    static func writeAll(_ fd: Int32, bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else {
                return false
            }
            return writeAll(fd, buffer: base, count: bytes.count)
        }
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

private enum SmokeSocketError: LocalizedError {
    case posix(String, Int32)

    var errorDescription: String? {
        switch self {
        case .posix(let operation, let code):
            return "\(operation) failed: \(String(cString: strerror(code)))"
        }
    }
}
