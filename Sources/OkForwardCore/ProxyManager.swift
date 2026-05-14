import Foundation

public final class ProxyManager {
    private let store: RuleStore
    private var proxies: [UUID: ForwardingProxy] = [:]
    private var observers: [UUID: () -> Void] = [:]

    public private(set) var rules: [ProxyRule] {
        didSet {
            store.save(rules)
        }
    }

    public private(set) var states: [UUID: ProxyState] = [:]

    public init(store: RuleStore = RuleStore()) {
        self.store = store
        self.rules = store.load()
    }

    @discardableResult
    public func addObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    public func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    public func startAll() {
        for rule in rules where rule.enabled {
            start(rule)
        }
        notify()
    }

    public func stopAll() {
        proxies.values.forEach { $0.stop() }
        proxies.removeAll()
        states = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, ProxyState.stopped) })
        notify()
    }

    public func restartAll() {
        stopAll()
        startAll()
    }

    public func add(_ rule: ProxyRule) {
        rules.append(rule)
        if rule.enabled {
            start(rule)
        } else {
            states[rule.id] = .stopped
        }
        notify()
    }

    public func removeRule(id: UUID) {
        proxies[id]?.stop()
        proxies.removeValue(forKey: id)
        states.removeValue(forKey: id)
        rules.removeAll { $0.id == id }
        notify()
    }

    public func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }

        rules[index].enabled = enabled

        if enabled {
            start(rules[index])
        } else {
            proxies[id]?.stop()
            proxies.removeValue(forKey: id)
            states[id] = .stopped
        }

        notify()
    }

    public func state(for rule: ProxyRule) -> ProxyState {
        states[rule.id] ?? .stopped
    }

    private func start(_ rule: ProxyRule) {
        proxies[rule.id]?.stop()

        let proxy = ForwardingProxy(rule: rule)
        proxy.onStateChange = { [weak self] id, state in
            self?.states[id] = state
            self?.notify()
        }

        proxies[rule.id] = proxy
        states[rule.id] = .starting
        proxy.start()
    }

    private func notify() {
        DispatchQueue.main.async {
            self.observers.values.forEach { $0() }
        }
    }
}
