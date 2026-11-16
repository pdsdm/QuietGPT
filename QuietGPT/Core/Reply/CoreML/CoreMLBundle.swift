import Foundation

nonisolated struct CoreMLBundle: Decodable, Sendable {
    struct Rope: Decodable, Sendable {
        let theta: Double
        let partial: Double
    }

    struct Spec: Decodable, Sendable {
        let hiddenSize: Int
        let numKvHeads: Int
        let headDim: Int
        let convKernel: Int
        let layerTypes: [String]
        let rope: [String: Rope]
        let slidingWindow: Int
        let eosTokenIds: [Int32]
    }

    struct Shapes: Decodable, Sendable {
        let ctx: Int
        let prefill: Int
    }

    struct Graph: Decodable, Sendable {
        let file: String
        let function: String?
    }

    struct Chunk: Decodable, Sendable {
        let name: String
        let layers: [Int]
        let models: [String: Graph]
    }

    struct HeadPart: Decodable, Sendable {
        let file: String
        let start: Int
        let end: Int
    }

    struct Head: Decodable, Sendable {
        let chunks: [HeadPart]
        let vocab: Int
    }

    struct Embedding: Decodable, Sendable {
        let file: String
        let scale: String
        let vocab: Int
        let hidden: Int
    }

    static let fullAttention = "full_attention"
    static let slidingAttention = "sliding_attention"
    static let attentionKinds = [fullAttention, slidingAttention]

    let spec: Spec
    let shapes: Shapes
    let ring: Bool
    let chunks: [Chunk]
    let head: Head
    let embedding: Embedding
    let contexts: [Int]?

    var sizes: [Int] {
        contexts ?? [shapes.ctx]
    }

    static func load(from folder: URL) throws -> CoreMLBundle {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CoreMLBundle.self, from: Data(contentsOf: folder.appending(path: "manifest.json")))
    }

    func isAttention(_ layer: Int) -> Bool {
        Self.attentionKinds.contains(spec.layerTypes[layer])
    }

    func kind(_ layer: Int) -> String {
        spec.layerTypes[layer]
    }

    func cacheLength(_ kind: String) -> Int {
        cacheLength(kind, size: shapes.ctx)
    }

    func cacheLength(_ kind: String, size: Int) -> Int {
        kind == Self.slidingAttention ? min(spec.slidingWindow, size) : size
    }

    func graph(_ chunk: Chunk, _ tag: String, size: Int) -> Graph? {
        guard let graph = chunk.models[tag] else { return nil }
        guard contexts != nil else { return graph }
        return Graph(file: graph.file, function: "\(tag)_\(size)")
    }

    func attentionLayers(_ chunk: Chunk) -> [Int] {
        chunk.layers.filter(isAttention)
    }

    func convLayers(_ chunk: Chunk) -> [Int] {
        chunk.layers.filter { !isAttention($0) }
    }

    func attentionKinds(_ chunk: Chunk) -> [String] {
        Self.attentionKinds.filter { kind in attentionLayers(chunk).contains { self.kind($0) == kind } }
    }
}
