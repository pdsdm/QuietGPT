import Darwin
import Foundation
import Testing
@testable import QuietGPT

struct NetworkMeterTests {
    private func makeWatch(key: String = "network.app", suite: String = UUID().uuidString) throws -> NetworkWatch {
        NetworkWatch(defaults: try #require(UserDefaults(suiteName: suite)), key: key)
    }

    private func loopback(port: UInt16 = 0) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return address
    }

    @Test func formatsBytes() {
        #expect(NetworkMeter.format(0) == "0 B")
        #expect(NetworkMeter.format(512) == "512 B")
        #expect(NetworkMeter.format(2_000_000).contains("MB"))
    }

    @Test func seesAnInternetSocketOfThisApp() throws {
        let before = NetworkMeter.ownSockets().count
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        defer { close(descriptor) }

        #expect(NetworkMeter.ownSockets().count == before + 1)
    }

    @Test func loopbackDoesNotCount() throws {
        let before = NetworkMeter.ownSockets().count
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = loopback()
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }

        #expect(bound == 0)
        #expect(NetworkMeter.ownSockets().count == before)
    }

    @Test func readsTheBytesSentOnATCPSocket() throws {
        let server = socket(AF_INET, SOCK_STREAM, 0)
        let client = socket(AF_INET, SOCK_STREAM, 0)
        defer {
            close(server)
            close(client)
        }
        var address = loopback()
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        try withUnsafeMutablePointer(to: &address) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try #require(bind(server, $0, size) == 0)
                try #require(listen(server, 1) == 0)
                try #require(getsockname(server, $0, &size) == 0)
                try #require(connect(client, $0, size) == 0)
            }
        }
        let message = Array(repeating: UInt8(7), count: 1000)
        #expect(send(client, message, message.count, 0) == 1000)

        #expect(NetworkMeter.sentBytes(onSocket: client) >= 1000)
    }

    @Test func watchCountsANewConnectionOnce() throws {
        let watch = try makeWatch()
        watch.scan()
        let start = watch.total.connections

        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        defer { close(descriptor) }
        watch.scan()
        watch.scan()

        #expect(watch.total.connections == start + 1)
    }

    @Test func aDuplicatedSocketCountsOnce() throws {
        let watch = try makeWatch()
        watch.scan()
        let start = watch.total.connections
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        var address = loopback()
        address.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        let copy = dup(descriptor)
        defer {
            close(descriptor)
            close(copy)
        }

        watch.scan()

        #expect(bound == 0)
        #expect(watch.total.connections == start + 1)
    }

    @Test func totalAddsTheExtensionsAndSurvivesARestart() throws {
        let suite = UUID().uuidString
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        defer { close(descriptor) }
        try makeWatch(key: "network.share", suite: suite).scan()
        try makeWatch(key: "network.app", suite: suite).scan()

        let reopened = try makeWatch(key: "network.app", suite: suite)

        #expect(reopened.total.connections >= 2)
    }
}
