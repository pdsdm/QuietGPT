import CryptoKit
import Foundation
import os

nonisolated struct Weights: Equatable, Sendable {
    let name: String
    let url: URL
    let sha256: String
    let bytes: Int64

    static let q8 = Weights(
        name: "LFM3-1.7B-Q8_0.gguf",
        url: URL(string: "https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/resolve/main/LFM3-1.7B-Q8_0.gguf")!,
        sha256: "8f6b24182258205e9e01e21f1f24a1f208c1e8115578825d202ce39976af20b6",
        bytes: 1_846_238_496
    )

    static let q4 = Weights(
        name: "LFM3-1.7B-QAD-Q4_0.gguf",
        url: URL(string: "https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/resolve/main/LFM3-1.7B-QAD-Q4_0.gguf")!,
        sha256: "43a7d09a0e9cba91b63eb7052488b9564569bddfd65754d2e426465e572a7452",
        bytes: 1_049_615_680
    )
}

@MainActor
@Observable
final class WeightStore {
    enum State: Equatable {
        case missing
        case downloading(Double)
        case verifying
        case ready
        case failed(String)
    }

    private static let logger = Logger(subsystem: "QuietGPT", category: "weights")
    private static let sessionID = "com.pdsdm.quietgpt.weights"

    let weights: Weights
    private(set) var state: State = .missing
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private let relay = DownloadRelay()

    init(weights: Weights) {
        self.weights = weights
        if FileManager.default.fileExists(atPath: markerURL.path), fileSize(fileURL) == weights.bytes {
            state = .ready
        }
        relay.store = self
    }

    nonisolated static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Weights", directoryHint: .isDirectory)
    }

    var fileURL: URL {
        Self.folder.appending(path: weights.name)
    }

    private var markerURL: URL {
        Self.folder.appending(path: weights.name + ".verified")
    }

    private var resumeURL: URL {
        Self.folder.appending(path: weights.name + ".resume")
    }

    func start() {
        switch state {
        case .ready, .verifying, .downloading:
            return
        case .missing, .failed:
            break
        }
        do {
            try prepareFolder()
        } catch {
            fail("Folder: \(error.localizedDescription)")
            return
        }
        if fileSize(fileURL) == weights.bytes {
            verify(fileURL)
            return
        }
        let session = session ?? makeSession()
        if let data = try? Data(contentsOf: resumeURL) {
            try? FileManager.default.removeItem(at: resumeURL)
            session.downloadTask(withResumeData: data).resume()
        } else {
            session.downloadTask(with: weights.url).resume()
        }
        state = .downloading(0)
        Self.logger.notice("Download started: \(self.weights.name, privacy: .public)")
    }

    func remove() {
        session?.invalidateAndCancel()
        session = nil
        for url in [fileURL, markerURL, resumeURL] {
            try? FileManager.default.removeItem(at: url)
        }
        state = .missing
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        let session = URLSession(configuration: configuration, delegate: relay, delegateQueue: nil)
        self.session = session
        return session
    }

    private func prepareFolder() throws {
        var folder = Self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    fileprivate func progress(_ written: Int64, of total: Int64) {
        guard case .downloading = state else { return }
        let expected = total > 0 ? total : weights.bytes
        state = .downloading(min(1, Double(written) / Double(expected)))
    }

    fileprivate func downloaded(_ file: URL) {
        verify(file)
    }

    fileprivate func failed(_ error: Error, resumeData: Data?) {
        if let resumeData {
            try? resumeData.write(to: resumeURL)
        }
        fail("Download: \(error.localizedDescription)")
    }

    private func verify(_ file: URL) {
        state = .verifying
        let weights = weights
        let target = fileURL
        let marker = markerURL
        Task {
            let started = ContinuousClock.now
            let hash = await Task.detached(priority: .utility) { Self.sha256(of: file) }.value
            guard hash == weights.sha256 else {
                try? FileManager.default.removeItem(at: file)
                fail("Hash mismatch")
                return
            }
            do {
                if file != target {
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.moveItem(at: file, to: target)
                }
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
                try Data(weights.sha256.utf8).write(to: marker)
                state = .ready
                Self.logger.notice("Weights ready: \(weights.name, privacy: .public), hash check \(started.duration(to: .now), privacy: .public)")
            } catch {
                fail("Move: \(error.localizedDescription)")
            }
        }
    }

    private func fail(_ reason: String) {
        state = .failed(reason)
        Self.logger.error("Weights failed: \(reason, privacy: .public)")
    }

    private func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    nonisolated private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private nonisolated final class DownloadRelay: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var store: WeightStore?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor [weak store] in
            store?.progress(totalBytesWritten, of: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let part = WeightStore.folder.appending(path: UUID().uuidString + ".part")
        do {
            try FileManager.default.moveItem(at: location, to: part)
        } catch {
            Task { @MainActor [weak store] in
                store?.failed(error, resumeData: nil)
            }
            return
        }
        Task { @MainActor [weak store] in
            store?.downloaded(part)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor [weak store] in
            store?.failed(error, resumeData: resumeData)
        }
    }
}
