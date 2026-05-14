import Foundation

public struct ProxyRule: Codable, Equatable, Identifiable {
    public var id: UUID
    public var bindHost: String
    public var listenPort: UInt16
    public var targetHost: String
    public var targetPort: UInt16
    public var enabled: Bool

    public init(
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

    public var displayName: String {
        "\(bindHost):\(listenPort) -> \(targetHost):\(targetPort)"
    }
}

public enum PortParser {
    public static func parse(_ value: String) -> UInt16? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = UInt16(trimmed), number > 0 else {
            return nil
        }

        return number
    }
}
