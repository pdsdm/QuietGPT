import Foundation
import SwiftData
import Testing
@testable import QuietGPT

struct ChatStoreTests {
    private let root: URL
    private let folder: URL
    private let legacy: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        folder = root.appending(path: "Chats", directoryHint: .isDirectory)
        legacy = root.appending(path: "Group", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    }

    private func write(_ name: String, in folder: URL) throws {
        try Data(name.utf8).write(to: folder.appending(path: name))
    }

    private func exists(_ name: String, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: name).path)
    }

    @Test func folderStaysOutOfBackups() throws {
        try ChatStore.prepare(folder: folder, legacyFolder: nil)

        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func movesOldChatsOutOfTheSharedFolder() throws {
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            try write(name, in: legacy)
        }
        try write("other.file", in: legacy)

        let url = try ChatStore.prepare(folder: folder, legacyFolder: legacy)

        #expect(url == folder.appending(path: "default.store"))
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            #expect(exists(name, in: folder))
            #expect(!exists(name, in: legacy))
        }
        #expect(exists("other.file", in: legacy))
    }

    @Test func keepsTheNewStoreAndRemovesAnOldCopy() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: folder.appending(path: "default.store"))
        try write("default.store", in: legacy)

        try ChatStore.prepare(folder: folder, legacyFolder: legacy)

        #expect(try Data(contentsOf: folder.appending(path: "default.store")) == Data("new".utf8))
        #expect(!exists("default.store", in: legacy))
    }

    @Test func movedChatsStillOpen() throws {
        let schema = Schema([Conversation.self, Message.self])
        do {
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: legacy.appending(path: "default.store"), cloudKitDatabase: .none))
            let context = ModelContext(old)
            context.insert(Conversation(title: "Kept"))
            try context.save()
        }

        let url = try ChatStore.prepare(folder: folder, legacyFolder: legacy)
        let moved = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))

        #expect(try ModelContext(moved).fetch(FetchDescriptor<Conversation>()).map(\.title) == ["Kept"])
    }
}
