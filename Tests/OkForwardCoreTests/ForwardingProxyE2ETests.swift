import Foundation
import Testing
@testable import OkForwardCore

struct ForwardingProxyE2ETests {
    @Test func forwardsBytesThroughLocalEchoServer() throws {
        let server = try EchoServer()
        defer { server.stop() }

        let listenPort = try TestSocket.reserveLoopbackPort()
        let proxy = ForwardingProxy(
            rule: ProxyRule(
                bindHost: "127.0.0.1",
                listenPort: listenPort,
                targetHost: "127.0.0.1",
                targetPort: server.port
            )
        )
        proxy.start()
        defer { proxy.stop() }

        #expect(waitUntilReady(proxy))

        let payload = Data("hello-through-okforward".utf8)
        let response = try TestSocket.sendAndReceive(payload, host: "127.0.0.1", port: listenPort)
        #expect(response == payload)
    }

    @Test func forwardsMultipleIndependentConnections() throws {
        let server = try EchoServer()
        defer { server.stop() }

        let listenPort = try TestSocket.reserveLoopbackPort()
        let proxy = ForwardingProxy(
            rule: ProxyRule(
                bindHost: "127.0.0.1",
                listenPort: listenPort,
                targetHost: "127.0.0.1",
                targetPort: server.port
            )
        )
        proxy.start()
        defer { proxy.stop() }

        #expect(waitUntilReady(proxy))

        for index in 0..<5 {
            let payload = Data("message-\(index)".utf8)
            let response = try TestSocket.sendAndReceive(payload, host: "127.0.0.1", port: listenPort)
            #expect(response == payload)
        }
    }

    @Test func disabledRuleDoesNotOpenListener() throws {
        let listenPort = try TestSocket.reserveLoopbackPort()
        let proxy = ForwardingProxy(
            rule: ProxyRule(
                bindHost: "127.0.0.1",
                listenPort: listenPort,
                targetHost: "127.0.0.1",
                targetPort: 9,
                enabled: false
            )
        )

        proxy.start()
        defer { proxy.stop() }

        #expect(proxy.state == .stopped)

        var didThrow = false
        do {
            let fd = try TestSocket.connect(host: "127.0.0.1", port: listenPort)
            TestSocket.close(fd)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    private func waitUntilReady(_ proxy: ForwardingProxy) -> Bool {
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
