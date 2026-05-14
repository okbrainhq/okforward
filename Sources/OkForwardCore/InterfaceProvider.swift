import Foundation

public struct NetworkInterface: Equatable {
    public let name: String
    public let address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }

    public var label: String {
        "\(address) (\(name))"
    }
}

public enum InterfaceProvider {
    public static func availableHosts() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = [
            NetworkInterface(name: "all IPv4", address: "0.0.0.0"),
            NetworkInterface(name: "loopback", address: "127.0.0.1")
        ]

        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return interfaces
        }

        defer {
            freeifaddrs(pointer)
        }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer {
                cursor = current.pointee.ifa_next
            }

            let interface = current.pointee
            guard let address = interface.ifa_addr else {
                continue
            }

            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0 else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            let result = getnameinfo(
                address,
                length,
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            let value = String(cString: host)
            guard !value.isEmpty, !value.contains("%") else {
                continue
            }

            let item = NetworkInterface(name: name, address: value)
            if !interfaces.contains(where: { $0.address == item.address }) {
                interfaces.append(item)
            }
        }

        return interfaces.sorted { lhs, rhs in
            if lhs.address == "0.0.0.0" { return true }
            if rhs.address == "0.0.0.0" { return false }
            if lhs.address == "127.0.0.1" { return true }
            if rhs.address == "127.0.0.1" { return false }
            return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }
}
