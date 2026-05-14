import Foundation
import Testing
@testable import OkForwardCore

struct RuleStoreTests {
    private let defaultsKey = "forwarding.rules.v1"

    @Test func ruleStoreRoundTripsRules() {
        let suite = makeDefaults()
        defer { cleanup(suite) }

        let store = RuleStore(defaults: suite.defaults)
        let rules = [
            ProxyRule(
                id: UUID(uuidString: "6CE387E2-0BF5-4769-9381-69F637ACB07A")!,
                bindHost: "192.168.64.1",
                listenPort: 2222,
                targetHost: "127.0.0.1",
                targetPort: 22,
                enabled: true
            ),
            ProxyRule(
                id: UUID(uuidString: "13BC2FDB-A159-4140-A7D7-35CC01971D7F")!,
                bindHost: "127.0.0.1",
                listenPort: 18080,
                targetHost: "localhost",
                targetPort: 8080,
                enabled: false
            )
        ]

        store.save(rules)

        #expect(store.load() == rules)
    }

    @Test func ruleStoreReturnsEmptyArrayForInvalidData() {
        let suite = makeDefaults()
        defer { cleanup(suite) }

        suite.defaults.set(Data("not-json".utf8), forKey: defaultsKey)

        #expect(RuleStore(defaults: suite.defaults).load() == [])
    }

    @Test func proxyManagerLoadsPersistedRules() {
        let suite = makeDefaults()
        defer { cleanup(suite) }

        let store = RuleStore(defaults: suite.defaults)
        let rules = [
            ProxyRule(bindHost: "127.0.0.1", listenPort: 9001, targetPort: 22),
            ProxyRule(bindHost: "0.0.0.0", listenPort: 9002, targetHost: "localhost", targetPort: 8080, enabled: false)
        ]
        store.save(rules)

        let manager = ProxyManager(store: RuleStore(defaults: suite.defaults))

        #expect(manager.rules == rules)
    }

    @Test func portParserRejectsInvalidPorts() {
        #expect(PortParser.parse(" 2222 ") == 2222)
        #expect(PortParser.parse("0") == nil)
        #expect(PortParser.parse("65536") == nil)
        #expect(PortParser.parse("abc") == nil)
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "dev.okforward.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func cleanup(_ suite: (defaults: UserDefaults, suiteName: String)) {
        suite.defaults.removePersistentDomain(forName: suite.suiteName)
    }
}
