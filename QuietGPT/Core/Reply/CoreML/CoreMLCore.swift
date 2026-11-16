import Accelerate
import CoreML
import CoreVideo
import Foundation
import llama

nonisolated final class CoreMLCore: @unchecked Sendable {
    private struct Part {
        let chunk: CoreMLBundle.Chunk
        let decode: MLModel
        let prefill: MLModel?
        let attention: [Int]
        let conv: [Int]
        let kinds: [String]
    }

    private struct Inputs {
        let hidden: MLMultiArray
        var cos: [String: MLMultiArray] = [:]
        var sin: [String: MLMultiArray] = [:]
        var mask: [String: MLMultiArray] = [:]
    }

    private static let backend: Void = llama_backend_init()

    let queue = DispatchQueue(label: "QuietGPT.coreml", qos: .userInitiated)
    let folder: URL
    private let compiledFolder: URL
    private let units: MLComputeUnits

    private(set) var bundle: CoreMLBundle?
    private var parts: [Part] = []
    private var heads: [(model: MLModel, start: Int, end: Int)] = []
    private var keys: [Int: MLMultiArray] = [:]
    private var values: [Int: MLMultiArray] = [:]
    private var convs: [Int: MLMultiArray] = [:]
    private var inverse: [String: [Float]] = [:]
    private var inputs: [Int: Inputs] = [:]
    private var headInput: MLMultiArray?
    private var embedding: Data?
    private var scales: [Float] = []
    private var vocabModel: OpaquePointer?
    private var vocab: OpaquePointer?
    private var logits: [Float] = []
    private var row: [Float] = []

    private(set) var pos = 0
    private(set) var predictSeconds = 0.0
    private var cached: [Int32] = []
    private var cachedConversation: UUID?
    private var cachedTurns = -1

    init(folder: URL, compiledFolder: URL, units: MLComputeUnits = .cpuAndNeuralEngine) {
        self.folder = folder
        self.compiledFolder = compiledFolder
        self.units = units
    }

    deinit {
        unload()
    }

    var isLoaded: Bool {
        bundle != nil
    }

    var context: Int {
        bundle?.shapes.ctx ?? 0
    }

    func unload() {
        parts = []
        heads = []
        keys = [:]
        values = [:]
        convs = [:]
        inputs = [:]
        headInput = nil
        embedding = nil
        if let vocabModel { llama_model_free(vocabModel) }
        vocabModel = nil
        vocab = nil
        bundle = nil
        pos = 0
        forgetAll()
    }

    func forget(_ conversationID: UUID) {
        guard cachedConversation == conversationID else { return }
        forgetAll()
    }

    func forgetAll() {
        cached = []
        cachedConversation = nil
        cachedTurns = -1
    }

    func load() throws {
        guard bundle == nil else { return }
        _ = Self.backend
        let bundle = try CoreMLBundle.load(from: folder)
        precondition(bundle.ring, "Core ML bundle without a ring buffer")
        try FileManager.default.createDirectory(at: compiledFolder, withIntermediateDirectories: true)
        var parts: [Part] = []
        for chunk in bundle.chunks {
            guard let decode = chunk.models["decode"] else { throw TextEngineError.notReady }
            let decodeModel = try model(decode)
            let prefillModel = try chunk.models["prefill"].map(model)
            parts.append(Part(
                chunk: chunk,
                decode: decodeModel,
                prefill: prefillModel,
                attention: bundle.attentionLayers(chunk),
                conv: bundle.convLayers(chunk),
                kinds: bundle.attentionKinds(chunk)
            ))
        }
        heads = try bundle.head.chunks.map { (try model(CoreMLBundle.Graph(file: $0.file, function: nil)), $0.start, $0.end) }
        self.parts = parts

        let spec = bundle.spec
        for layer in 0..<spec.layerTypes.count {
            if bundle.isAttention(layer) {
                let length = bundle.cacheLength(bundle.kind(layer))
                keys[layer] = try Self.surfaceArray(heads: spec.numKvHeads, rows: length, width: spec.headDim)
                values[layer] = try Self.surfaceArray(heads: spec.numKvHeads, rows: length, width: spec.headDim)
            } else {
                convs[layer] = try MLMultiArray(shape: [1, spec.hiddenSize, spec.convKernel - 1].map { NSNumber(value: $0) }, dataType: .float16)
            }
        }
        for (kind, rope) in spec.rope {
            inverse[kind] = CoreMLMath.inverseFrequencies(theta: rope.theta, partial: rope.partial, headDim: spec.headDim)
        }
        for seq in Set([1, bundle.shapes.prefill]) {
            var set = Inputs(hidden: try Self.array([1, seq, spec.hiddenSize]))
            for kind in CoreMLBundle.attentionKinds where spec.rope[kind] != nil {
                set.cos[kind] = try Self.array([1, seq, spec.headDim])
                set.sin[kind] = try Self.array([1, seq, spec.headDim])
                set.mask[kind] = try Self.array([1, 1, seq, bundle.cacheLength(kind) + seq])
            }
            inputs[seq] = set
        }
        headInput = try Self.array([1, 1, spec.hiddenSize])
        embedding = try Data(contentsOf: folder.appending(path: bundle.embedding.file), options: .alwaysMapped)
        let scaleData = try Data(contentsOf: folder.appending(path: bundle.embedding.scale))
        scales = scaleData.withUnsafeBytes { raw in raw.bindMemory(to: Float16.self).map(Float.init) }
        guard embedding?.count == bundle.embedding.vocab * bundle.embedding.hidden, scales.count == bundle.embedding.vocab else {
            throw TextEngineError.notReady
        }
        logits = [Float](repeating: 0, count: bundle.head.vocab)
        row = [Float](repeating: 0, count: spec.hiddenSize)

        var params = llama_model_default_params()
        params.vocab_only = true
        guard let vocabModel = llama_model_load_from_file(folder.appending(path: "tokenizer.gguf").path, params) else {
            throw TextEngineError.notReady
        }
        self.vocabModel = vocabModel
        vocab = llama_model_get_vocab(vocabModel)
        self.bundle = bundle
        try reset()
    }

    func reset() throws {
        pos = 0
        for array in Array(keys.values) + Array(values.values) + Array(convs.values) {
            array.withUnsafeMutableBytes { raw, _ in
                _ = memset(raw.baseAddress!, 0, raw.count)
            }
        }
    }

    func tokenize(_ text: String) throws -> [Int32] {
        guard let vocab else { throw TextEngineError.notReady }
        return LlamaVocab.tokenize(text, vocab: vocab)
    }

    func piece(_ token: Int32) -> [UInt8] {
        guard let vocab else { return [] }
        return LlamaVocab.piece(token, vocab: vocab)
    }

    func isEnd(_ token: Int32) -> Bool {
        if bundle?.spec.eosTokenIds.contains(token) == true { return true }
        guard let vocab else { return false }
        return llama_vocab_is_eog(vocab, token)
    }

    func feed(_ ids: [Int32], isCancelled: () -> Bool = { false }) throws -> [Float] {
        guard let bundle else { throw TextEngineError.notReady }
        guard !ids.isEmpty else { throw TextEngineError.failed }
        var offset = 0
        var last: MLMultiArray?
        for seq in CoreMLMath.passes(count: ids.count, prefill: bundle.shapes.prefill) {
            if isCancelled() { throw CancellationError() }
            last = try autoreleasepool { try forward(Array(ids[offset..<offset + seq])) }
            offset += seq
        }
        return try autoreleasepool { try head(last!) }
    }

    func step(_ token: Int32) throws -> [Float] {
        try autoreleasepool { try head(forward([token])) }
    }

    private func forward(_ ids: [Int32]) throws -> MLMultiArray {
        guard let bundle, let set = inputs[ids.count] else { throw TextEngineError.failed }
        let seq = ids.count
        guard pos + seq <= bundle.shapes.ctx else { throw TextEngineError.tooLong }
        embed(ids, into: set.hidden)
        for (kind, inverse) in inverse {
            guard let cosArray = set.cos[kind], let sinArray = set.sin[kind], let maskArray = set.mask[kind] else { continue }
            let (cosines, sines) = CoreMLMath.rope(inverse: inverse, start: pos, count: seq)
            Self.write(cosines, into: cosArray)
            Self.write(sines, into: sinArray)
            let mask = CoreMLMath.mask(
                sliding: kind == CoreMLBundle.slidingAttention,
                length: bundle.cacheLength(kind),
                seq: seq,
                pos: pos,
                window: bundle.spec.slidingWindow
            )
            Self.write(mask, into: maskArray)
        }
        var hidden = set.hidden
        for part in parts {
            var features: [String: MLFeatureValue] = ["hidden": MLFeatureValue(multiArray: hidden)]
            for kind in part.kinds {
                features["cos_\(kind)"] = MLFeatureValue(multiArray: set.cos[kind]!)
                features["sin_\(kind)"] = MLFeatureValue(multiArray: set.sin[kind]!)
                features["mask_\(kind)"] = MLFeatureValue(multiArray: set.mask[kind]!)
            }
            for layer in part.attention {
                features["k_\(layer)"] = MLFeatureValue(multiArray: keys[layer]!)
                features["v_\(layer)"] = MLFeatureValue(multiArray: values[layer]!)
            }
            for layer in part.conv {
                features["conv_\(layer)"] = MLFeatureValue(multiArray: convs[layer]!)
            }
            let model = seq == 1 ? part.decode : (part.prefill ?? part.decode)
            let started = DispatchTime.now().uptimeNanoseconds
            let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: features))
            predictSeconds += Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
            for layer in part.attention {
                let length = bundle.cacheLength(bundle.kind(layer))
                try Self.store(out.featureValue(for: "k_\(layer)_out")?.multiArrayValue, into: keys[layer]!, pos: pos, length: length)
                try Self.store(out.featureValue(for: "v_\(layer)_out")?.multiArrayValue, into: values[layer]!, pos: pos, length: length)
            }
            for layer in part.conv {
                guard let state = out.featureValue(for: "conv_\(layer)_out")?.multiArrayValue else { throw TextEngineError.failed }
                Self.copy(state, into: convs[layer]!)
            }
            guard let next = out.featureValue(for: "hidden_out")?.multiArrayValue else { throw TextEngineError.failed }
            hidden = next
        }
        pos += seq
        return hidden
    }

    private func head(_ hidden: MLMultiArray) throws -> [Float] {
        guard let headInput else { throw TextEngineError.notReady }
        let seq = hidden.shape[1].intValue
        let width = hidden.shape[2].intValue
        let strides = hidden.strides.map(\.intValue)
        hidden.withUnsafeBufferPointer(ofType: Float16.self) { source in
            headInput.withUnsafeMutableBufferPointer(ofType: Float16.self) { target, targetStrides in
                let base = (seq - 1) * strides[1]
                for i in 0..<width {
                    target[i * targetStrides[2]] = source[base + i * strides[2]]
                }
            }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["hidden": MLFeatureValue(multiArray: headInput)])
        for part in heads {
            let started = DispatchTime.now().uptimeNanoseconds
            let result = try part.model.prediction(from: provider)
            predictSeconds += Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
            guard let out = result.featureValue(for: "logits")?.multiArrayValue else {
                throw TextEngineError.failed
            }
            let strides = out.strides.map(\.intValue)
            out.withUnsafeBufferPointer(ofType: Float16.self) { source in
                logits.withUnsafeMutableBufferPointer { target in
                    let count = part.end - part.start
                    if strides[2] == 1 {
                        var input = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source.baseAddress!), height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
                        var output = vImage_Buffer(data: target.baseAddress! + part.start, height: 1, width: vImagePixelCount(count), rowBytes: count * 4)
                        vImageConvert_Planar16FtoPlanarF(&input, &output, 0)
                    } else {
                        for i in 0..<count {
                            target[part.start + i] = Float(source[i * strides[2]])
                        }
                    }
                }
            }
        }
        return logits
    }

    private func embed(_ ids: [Int32], into array: MLMultiArray) {
        guard let bundle, let embedding else { return }
        let width = bundle.embedding.hidden
        embedding.withUnsafeBytes { raw in
            let table = raw.bindMemory(to: Int8.self).baseAddress!
            array.withUnsafeMutableBufferPointer(ofType: Float16.self) { target, strides in
                row.withUnsafeMutableBufferPointer { values in
                    for (t, id) in ids.enumerated() {
                        let index = Int(id)
                        vDSP_vflt8(table + index * width, 1, values.baseAddress!, 1, vDSP_Length(width))
                        var scale = scales[index]
                        vDSP_vsmul(values.baseAddress!, 1, &scale, values.baseAddress!, 1, vDSP_Length(width))
                        let base = t * strides[1]
                        for i in 0..<width {
                            target[base + i * strides[2]] = Float16(values[i])
                        }
                    }
                }
            }
        }
    }

    private func model(_ graph: CoreMLBundle.Graph) throws -> MLModel {
        let package = folder.appending(path: graph.file)
        let compiled = compiledFolder.appending(path: package.deletingPathExtension().lastPathComponent + ".mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
            let temporary = try Self.compile(package)
            try? FileManager.default.removeItem(at: compiled)
            try FileManager.default.moveItem(at: temporary, to: compiled)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        configuration.functionName = graph.function
        do {
            return try MLModel(contentsOf: compiled, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: compiled)
            try FileManager.default.moveItem(at: try Self.compile(package), to: compiled)
            return try MLModel(contentsOf: compiled, configuration: configuration)
        }
    }

    private static func compile(_ package: URL) throws -> URL {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<URL, Error> = .failure(TextEngineError.notReady)
        Task.detached {
            do {
                result = .success(try await MLModel.compileModel(at: package))
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }

    private static func array(_ shape: [Int]) throws -> MLMultiArray {
        try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float16)
    }

    private static func surfaceArray(heads: Int, rows: Int, width: Int) throws -> MLMultiArray {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        let status = CVPixelBufferCreate(nil, width, heads * rows, kCVPixelFormatType_OneComponent16Half, attributes, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw TextEngineError.failed }
        return MLMultiArray(pixelBuffer: buffer, shape: [1, heads, rows, width].map { NSNumber(value: $0) })
    }

    private static func write(_ values: [Float16], into array: MLMultiArray) {
        let shape = array.shape.map(\.intValue)
        let width = shape[shape.count - 1]
        let rows = values.count / width
        array.withUnsafeMutableBufferPointer(ofType: Float16.self) { target, strides in
            let rowStride = strides[strides.count - 2]
            let column = strides[strides.count - 1]
            values.withUnsafeBufferPointer { source in
                for r in 0..<rows {
                    if column == 1 {
                        (target.baseAddress! + r * rowStride).update(from: source.baseAddress! + r * width, count: width)
                    } else {
                        for c in 0..<width {
                            target[r * rowStride + c * column] = source[r * width + c]
                        }
                    }
                }
            }
        }
    }

    private static func store(_ new: MLMultiArray?, into cache: MLMultiArray, pos: Int, length: Int) throws {
        guard let new else { throw TextEngineError.failed }
        let heads = new.shape[1].intValue
        let seq = new.shape[2].intValue
        let width = new.shape[3].intValue
        let s = new.strides.map(\.intValue)
        new.withUnsafeBufferPointer(ofType: Float16.self) { source in
            cache.withUnsafeMutableBufferPointer(ofType: Float16.self) { target, t in
                for h in 0..<heads {
                    for r in 0..<seq {
                        let row = CoreMLMath.cacheRow(position: pos + r, length: length)
                        let from = h * s[1] + r * s[2]
                        let to = h * t[1] + row * t[2]
                        if s[3] == 1, t[3] == 1 {
                            (target.baseAddress! + to).update(from: source.baseAddress! + from, count: width)
                        } else {
                            for c in 0..<width {
                                target[to + c * t[3]] = source[from + c * s[3]]
                            }
                        }
                    }
                }
            }
        }
    }

    private static func copy(_ source: MLMultiArray, into target: MLMultiArray) {
        let shape = target.shape.map(\.intValue)
        let s = source.strides.map(\.intValue)
        source.withUnsafeBufferPointer(ofType: Float16.self) { from in
            target.withUnsafeMutableBufferPointer(ofType: Float16.self) { to, t in
                for a in 0..<shape[1] {
                    for b in 0..<shape[2] {
                        to[a * t[1] + b * t[2]] = from[a * s[1] + b * s[2]]
                    }
                }
            }
        }
    }

    func generate(
        conversation: UUID,
        turns: Int,
        full: String,
        next: String,
        maxTokens: Int,
        sampler: inout CoreMLSampler,
        isCancelled: () -> Bool,
        yield: (String) -> Void
    ) throws -> EngineMetrics {
        var metrics = EngineMetrics()
        predictSeconds = 0
        if !isLoaded {
            let started = Date()
            try load()
            metrics.loadSeconds = Date().timeIntervalSince(started)
        }
        let reuse = cachedConversation == conversation && cachedTurns == turns && !cached.isEmpty
        var tokens: [Int32]
        let fresh: [Int32]
        if reuse {
            fresh = try tokenize(next)
            tokens = cached + fresh
            metrics.reusedTokens = cached.count
        } else {
            try reset()
            forgetAll()
            fresh = try tokenize(full)
            tokens = fresh
        }
        metrics.promptTokens = tokens.count
        cachedConversation = nil
        guard tokens.count + 64 <= context else {
            try reset()
            forgetAll()
            throw TextEngineError.tooLong
        }
        let limit = min(maxTokens, context - tokens.count)
        let prefillStart = Date()
        var current: [Float]
        do {
            current = try feed(fresh, isCancelled: isCancelled)
        } catch {
            try? reset()
            throw error
        }
        metrics.prefillSeconds = Date().timeIntervalSince(prefillStart)

        var generated: [Int32] = []
        var bytes: [UInt8] = []
        let decodeStart = Date()
        while generated.count < limit, !isCancelled() {
            let token = current.withUnsafeMutableBufferPointer { sampler.sample($0, recent: generated[...]) }
            if isEnd(token) { break }
            bytes += piece(token)
            tokens.append(token)
            generated.append(token)
            metrics.generatedTokens += 1
            if metrics.firstTokenSeconds == nil {
                metrics.firstTokenSeconds = Date().timeIntervalSince(prefillStart)
            }
            if let text = String(validating: bytes, as: UTF8.self) {
                yield(text)
            }
            guard pos < context else { break }
            do {
                current = try step(token)
            } catch {
                try? reset()
                throw error
            }
        }
        metrics.decodeSeconds = Date().timeIntervalSince(decodeStart)
        if pos == tokens.count {
            cached = tokens
            cachedConversation = conversation
            cachedTurns = turns + 2
        }
        (metrics.footprintMB, metrics.peakMB) = EngineMetrics.memory()
        metrics.thermal = EngineMetrics.thermal()
        metrics.predictSeconds = predictSeconds
        return metrics
    }
}
