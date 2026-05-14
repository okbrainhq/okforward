import Foundation

struct ProxyRule: Codable, Equatable, Identifiable {
    var id: UUID
    var bindHost: String
    var listenPort: UInt16
    var targetHost: String
    var targetPort: UInt16
    var enabled: Bool

    init(
        id: UUID = UUID(),
        bindHost: String,
        listenPort: UInt16,
        targetHost: String = "127.0.0.1",
        targetPort: UInt16,
        enabled: Bool = true
    ) {
        self.id = id
        self.bindHost = bindHost
        self.listenPort = listenPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.enabled = enabled
    }

    var displayName: String {
        "\(bindHost):\(listenPort) -> \(targetHost):\(targetPort)"
    }
}

enum PortParser {
    static func parse(_ value: String) -> UInt16? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = UInt16(trimmed), number > 0 else {
            return nil
        }

        return number
    }
}
