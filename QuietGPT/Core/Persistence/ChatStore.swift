import Foundation
import OSLog
import SwiftData

enum ChatStore {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "quietgpt", category: "store")
    private static let fileName = "default.store"
    private static let folderName = "Chats"

    static func makeContainer() -> ModelContainer {
        let schema = Schema([Conversation.self, Message.self])
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = try prepare(folder: support.appending(path: folderName, directoryHint: .isDirectory), legacyFolder: legacyFolder)
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        } catch {
            logger.error("Chat store failed: \(String(describing: error), privacy: .public)")
        }
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        } catch {
            fatalError("Chat store failed: \(error)")
        }
    }

    private static var legacyFolder: URL? {
        StyleStore.group
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    @discardableResult
    static func prepare(folder: URL, legacyFolder: URL?) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try protect(folder)

        let store = folder.appending(path: fileName)
        guard let legacyFolder, manager.fileExists(atPath: legacyFolder.appending(path: fileName).path) else {
            return store
        }
        guard !manager.fileExists(atPath: store.path) else {
            try removeStoreFiles(in: legacyFolder)
            return store
        }

        let files = try storeFiles(in: legacyFolder)
        var copied: [URL] = []
        do {
            for file in files {
                let target = folder.appending(path: file.lastPathComponent)
                try manager.copyItem(at: file, to: target)
                copied.append(target)
            }
            for target in copied {
                try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
            }
        } catch {
            for target in copied {
                try? manager.removeItem(at: target)
            }
            logger.error("Chat store move failed: \(String(describing: error), privacy: .public)")
            return legacyFolder.appending(path: fileName)
        }
        try removeStoreFiles(in: legacyFolder)
        return store
    }

    private static func protect(_ folder: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: folder.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = folder
        try url.setResourceValues(values)
    }

    private static func storeFiles(in folder: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(fileName) }
    }

    private static func removeStoreFiles(in folder: URL) throws {
        for file in try storeFiles(in: folder) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
