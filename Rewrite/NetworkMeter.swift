import Darwin
import Foundation
import Observation

struct OwnSocket: Hashable {
    var descriptor: Int32
    var port: UInt16
    var sent: UInt64
}

enum NetworkMeter {
    private static let maxDescriptors: Int32 = 4096

    static func ownSockets() -> [OwnSocket] {
        (0..<min(getdtablesize(), maxDescriptors)).compactMap { ownSocket($0) }
    }

    static func sentBytes(onSocket descriptor: Int32) -> UInt64 {
        var kind: Int32 = 0
        var kindSize = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &kind, &kindSize) == 0, kind == SOCK_STREAM else { return 0 }
        var info = tcp_connection_info()
        var size = socklen_t(MemoryLayout<tcp_connection_info>.size)
        guard getsockopt(descriptor, IPPROTO_TCP, TCP_CONNECTION_INFO, &info, &size) == 0 else { return 0 }
        return info.tcpi_txbytes
    }

    static func format(_ bytes: UInt64) -> String {
        guard bytes >= 1024 else { return "\(bytes) B" }
        return bytes.formatted(.byteCount(style: .file))
    }

    private static func ownSocket(_ descriptor: Int32) -> OwnSocket? {
        var stats = Darwin.stat()
        guard fstat(descriptor, &stats) == 0, stats.st_mode & S_IFMT == S_IFSOCK else { return nil }
        guard let local = address(of: descriptor, using: getsockname), !isLoopback(local) else { return nil }
        guard local.ss_family == UInt8(AF_INET) || local.ss_family == UInt8(AF_INET6) else { return nil }
        if let peer = address(of: descriptor, using: getpeername), isLoopback(peer) { return nil }
        return OwnSocket(descriptor: descriptor, port: port(of: local), sent: sentBytes(onSocket: descriptor))
    }

    private static func address(
        of descriptor: Int32,
        using call: (Int32, UnsafeMutablePointer<sockaddr>, UnsafeMutablePointer<socklen_t>) -> Int32
    ) -> sockaddr_storage? {
        var storage = sockaddr_storage()
        var size = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { call(descriptor, $0, &size) }
        }
        return result == 0 ? storage : nil
    }

    private static func isLoopback(_ storage: sockaddr_storage) -> Bool {
        let family = Int32(storage.ss_family)
        return withUnsafeBytes(of: storage) { raw in
            switch family {
            case AF_INET:
                let address = raw.load(fromByteOffset: MemoryLayout.offset(of: \sockaddr_in.sin_addr)!, as: in_addr.self)
                return UInt32(bigEndian: address.s_addr) >> 24 == 127
            case AF_INET6:
                let offset = MemoryLayout.offset(of: \sockaddr_in6.sin6_addr)!
                let bytes = raw[offset..<(offset + 16)]
                return bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            default:
                return false
            }
        }
    }

    private static func port(of storage: sockaddr_storage) -> UInt16 {
        withUnsafeBytes(of: storage) { raw in
            UInt16(bigEndian: raw.load(fromByteOffset: MemoryLayout.offset(of: \sockaddr_in.sin_port)!, as: UInt16.self))
        }
    }
}

struct NetworkLedger: Codable, Equatable {
    var sentBytes: UInt64 = 0
    var connections = 0

    static func + (left: NetworkLedger, right: NetworkLedger) -> NetworkLedger {
        NetworkLedger(
            sentBytes: left.sentBytes + right.sentBytes,
            connections: left.connections + right.connections
        )
    }
}

@Observable
final class NetworkWatch {
    static let shared = NetworkWatch(defaults: sharedDefaults, key: ownKey)

    private static var sharedDefaults: UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return UserDefaults(suiteName: "network.tests") ?? .standard
        }
        #endif
        return StyleStore.shared
    }

    private static let keys = ["network.app", "network.share", "network.keyboard"]

    private static var ownKey: String {
        let identifier = Bundle.main.bundleIdentifier ?? ""
        if identifier.hasSuffix(".share") { return "network.share" }
        if identifier.hasSuffix(".keyboard") { return "network.keyboard" }
        return "network.app"
    }

    private(set) var total = NetworkLedger()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private var own: NetworkLedger
    @ObservationIgnored private var seen: [OwnSocket: UInt64] = [:]

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
        own = Self.ledger(in: defaults, key: key)
        refresh()
    }

    func scan() {
        let sockets = NetworkMeter.ownSockets()
        var current: [OwnSocket: UInt64] = [:]
        for socket in sockets {
            var identity = socket
            identity.sent = 0
            if socket.port != 0 {
                identity.descriptor = -1
            }
            if let last = seen[identity] {
                own.sentBytes += socket.sent >= last ? socket.sent - last : 0
            } else {
                own.connections += 1
                own.sentBytes += socket.sent
            }
            current[identity] = socket.sent
        }
        seen = current
        save()
    }

    func refresh() {
        let next = Self.keys.reduce(NetworkLedger()) { sum, name in
            sum + (name == key ? own : Self.ledger(in: defaults, key: name))
        }
        if next != total {
            total = next
        }
    }

    private func save() {
        if own != Self.ledger(in: defaults, key: key), let data = try? JSONEncoder().encode(own) {
            defaults.set(data, forKey: key)
        }
        refresh()
    }

    private static func ledger(in defaults: UserDefaults, key: String) -> NetworkLedger {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(NetworkLedger.self, from: $0) } ?? NetworkLedger()
    }
}
