import Foundation

final class RuleStore {
    private let key = "forwarding.rules.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ProxyRule] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ProxyRule].self, from: data)
        } catch {
            NSLog("Failed to decode forwarding rules: \(error)")
            return []
        }
    }

    func save(_ rules: [ProxyRule]) {
        do {
            let data = try JSONEncoder().encode(rules)
            defaults.set(data, forKey: key)
        } catch {
            NSLog("Failed to save forwarding rules: \(error)")
        }
    }
}
