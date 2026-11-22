import Foundation
import Testing
@testable import QuietGPT

struct CoreMLBundleTests {
    static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Convert/bundles/lfm3-lut8-dyn-app")

    static var isPresent: Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: "manifest.json").path)
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: Self.folder.appending(path: path).path)
    }

    @Test(.enabled(if: isPresent)) func bundleHasEveryFileItNames() throws {
        let bundle = try CoreMLBundle.load(from: Self.folder)
        let files = bundle.chunks.flatMap { $0.models.values.map(\.file) } + bundle.head.chunks.map(\.file) + [bundle.embedding.file, bundle.embedding.scale, "tokenizer.gguf"]
        #expect(files.filter { !exists($0) } == [])
    }

    @Test(.enabled(if: isPresent)) func bundleCoversEveryLayerAndToken() throws {
        let bundle = try CoreMLBundle.load(from: Self.folder)
        #expect(bundle.chunks.flatMap(\.layers) == Array(bundle.spec.layerTypes.indices))
        let parts = bundle.head.chunks.sorted { $0.start < $1.start }
        #expect(parts.first?.start == 0)
        #expect(parts.last?.end == bundle.head.vocab)
        #expect(zip(parts, parts.dropFirst()).allSatisfy { $0.end == $1.start })
        #expect(bundle.embedding.vocab == bundle.head.vocab)
        #expect(bundle.embedding.hidden == bundle.spec.hiddenSize)
        #expect(bundle.chunks.allSatisfy { $0.models["prefill"] != nil && $0.models["decode"] != nil })
    }
}
