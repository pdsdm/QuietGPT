import Accelerate
import CoreML
import CoreVideo
import Foundation
import llama
import os

nonisolated final class CoreMLCore: @unchecked Sendable {
    private struct Part {
        let chunk: CoreMLBundle.Chunk
        let decode: MLModel
        let prefill: CoreMLBundle.Graph?
        let attention: [Int]
        let conv: [Int]
        let kinds: [String]
    }

    private struct Snapshot {
        let tokens: [Int32]
        let pos: Int
        let arrays: [String: Data]
    }

    private struct Inputs {
        let hidden: MLMultiArray
        var cos: [String: MLMultiArray] = [:]
        var sin: [String: MLMultiArray] = [:]
        var mask: [String: MLMultiArray] = [:]
    }

    private static let backend: Void = llama_backend_init()
    private static let logger = Logger(subsystem: "QuietGPT", category: "coreml")

    let queue = DispatchQueue(label: "QuietGPT.coreml", qos: .userInitiated)
    private let warmQueue = DispatchQueue(label: "QuietGPT.coreml.warm", qos: .utility)
    static let reserve = 768
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
    private(set) var size = 0
    private(set) var predictSeconds = 0.0
    private var cached: [Int32] = []
    private var cachedConversation: UUID?
    private var cachedTurns = -1
    private var snapshot: Snapshot?

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
        bundle == nil ? 0 : size
    }

    var sizes: [Int] {
        bundle?.sizes ?? []
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
        snapshot = nil
        pos = 0
        size = 0
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
        size = bundle.sizes[0]
        try loadParts(bundle, warm: true)
        heads = try bundle.head.chunks.map { (try model(CoreMLBundle.Graph(file: $0.file, function: nil)), $0.start, $0.end) }
        let spec = bundle.spec
        for (kind, rope) in spec.rope {
            inverse[kind] = CoreMLMath.inverseFrequencies(theta: rope.theta, partial: rope.partial, headDim: spec.headDim)
        }
        try makeCaches(bundle, keeping: 0)
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

    private func loadParts(_ bundle: CoreMLBundle, warm: Bool) throws {
        var parts: [Part] = []
        for chunk in bundle.chunks {
            guard let decode = bundle.graph(chunk, "decode", size: size) else { throw TextEngineError.notReady }
            let decodeModel = try model(decode)
            let prefill = bundle.graph(chunk, "prefill", size: size)
            if warm, let prefill {
                try autoreleasepool { _ = try model(prefill) }
            }
            parts.append(Part(
                chunk: chunk,
                decode: decodeModel,
                prefill: prefill,
                attention: bundle.attentionLayers(chunk),
                conv: bundle.convLayers(chunk),
                kinds: bundle.attentionKinds(chunk)
            ))
        }
        self.parts = parts
    }

    private func makeCaches(_ bundle: CoreMLBundle, keeping rows: Int) throws {
        let spec = bundle.spec
        var newKeys: [Int: MLMultiArray] = [:]
        var newValues: [Int: MLMultiArray] = [:]
        for layer in 0..<spec.layerTypes.count {
            if bundle.isAttention(layer) {
                let length = bundle.cacheLength(bundle.kind(layer), size: size)
                let k = try Self.surfaceArray(heads: spec.numKvHeads, rows: length, width: spec.headDim)
                let v = try Self.surfaceArray(heads: spec.numKvHeads, rows: length, width: spec.headDim)
                if let oldK = keys[layer], let oldV = values[layer] {
                    let oldLength = oldK.shape[2].intValue
                    let count = oldLength == length ? length : min(rows, length, oldLength)
                    Self.copyRows(oldK, into: k, rows: count)
                    Self.copyRows(oldV, into: v, rows: count)
                }
                newKeys[layer] = k
                newValues[layer] = v
            } else if convs[layer] == nil {
                convs[layer] = try MLMultiArray(shape: [1, spec.hiddenSize, spec.convKernel - 1].map { NSNumber(value: $0) }, dataType: .float16)
            }
        }
        keys = newKeys
        values = newValues
        inputs = [:]
        for seq in Set([1, bundle.shapes.prefill]) {
            var set = Inputs(hidden: try Self.array([1, seq, spec.hiddenSize]))
            for kind in CoreMLBundle.attentionKinds where spec.rope[kind] != nil {
                set.cos[kind] = try Self.array([1, seq, spec.headDim])
                set.sin[kind] = try Self.array([1, seq, spec.headDim])
                set.mask[kind] = try Self.array([1, 1, seq, bundle.cacheLength(kind, size: size) + seq])
            }
            inputs[seq] = set
        }
    }

    func resize(to newSize: Int) throws {
        guard let bundle, newSize != size, bundle.sizes.contains(newSize), pos <= newSize else { return }
        let started = Date()
        let old = size
        parts = []
        size = newSize
        do {
            try makeCaches(bundle, keeping: pos)
            try loadParts(bundle, warm: false)
        } catch {
            unload()
            throw error
        }
        let seconds = Date().timeIntervalSince(started)
        Self.logger.notice("Context \(old) to \(newSize) at \(self.pos) tokens in \(seconds, format: .fixed(precision: 2), privacy: .public) s")
    }

    func target(for need: Int) -> Int? {
        sizes.first { need <= $0 }
    }

    func adapt() {
        guard isLoaded, sizes.count > 1 else { return }
        let used = cachedConversation == nil ? 0 : pos
        let need = used + Self.reserve
        var next = size
        if need > size {
            next = target(for: need) ?? sizes[sizes.count - 1]
        } else if let smaller = sizes.first(where: { need <= $0 - 256 }), smaller < size {
            next = smaller
        }
        guard next != size else { return }
        if used == 0 {
            pos = 0
        }
        do {
            try resize(to: next)
        } catch {
            Self.logger.error("Context change failed: \(String(describing: error), privacy: .public)")
        }
    }

    func prewarm() {
        guard let bundle, bundle.sizes.count > 1 else { return }
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let system = ProcessInfo.processInfo.operatingSystemVersionString.filter { $0.isNumber || $0 == "." }
        let install = Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent
        let marker = compiledFolder.appending(path: "warm-\(build)-\(system)-\(install)")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let graphs = bundle.sizes.dropFirst().flatMap { size in
            bundle.chunks.flatMap { chunk in ["decode", "prefill"].compactMap { bundle.graph(chunk, $0, size: size) } }
        }
        warmQueue.async { [self] in
            let started = Date()
            for graph in graphs {
                do {
                    try autoreleasepool { _ = try model(graph) }
                } catch {
                    Self.logger.error("Warm failed for \(graph.function ?? "main", privacy: .public): \(String(describing: error), privacy: .public)")
                    return
                }
            }
            FileManager.default.createFile(atPath: marker.path, contents: nil)
            let seconds = Date().timeIntervalSince(started)
            Self.logger.notice("Larger contexts warmed in \(seconds, format: .fixed(precision: 1), privacy: .public) s")
        }
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
        guard let last = try advance(ids, isCancelled: isCancelled) else { throw TextEngineError.failed }
        return try autoreleasepool { try head(last) }
    }

    func warm(prefix text: String) throws {
        try load()
        let prefix = try tokenize(text)
        guard snapshot?.tokens != prefix, !prefix.isEmpty else { return }
        try reset()
        forgetAll()
        _ = try advance(prefix)
        snapshot = Snapshot(tokens: prefix, pos: pos, arrays: cacheArrays().mapValues(save))
    }

    private func usedRows(_ array: MLMultiArray) -> Int? {
        let shape = array.shape.map(\.intValue)
        guard shape.count == 4, shape[2] == context, array.strides.last?.intValue == 1 else { return nil }
        return min(pos, shape[2])
    }

    private func save(_ array: MLMultiArray) -> Data {
        guard let rows = usedRows(array) else {
            return array.withUnsafeMutableBytes { raw, _ in Data(raw) }
        }
        let heads = array.shape[1].intValue
        let width = array.shape[3].intValue
        var data = Data(count: heads * rows * width * 2)
        array.withUnsafeMutableBufferPointer(ofType: Float16.self) { source, strides in
            data.withUnsafeMutableBytes { raw in
                let target = raw.bindMemory(to: Float16.self).baseAddress!
                for h in 0..<heads {
                    for r in 0..<rows {
                        (target + (h * rows + r) * width).update(from: source.baseAddress! + h * strides[1] + r * strides[2], count: width)
                    }
                }
            }
        }
        return data
    }

    func begin(prefix text: String, ids: [Int32]) throws -> Int {
        try reset()
        let prefix = try tokenize(text)
        guard prefix.count < ids.count, ids.starts(with: prefix) else { return 0 }
        if !restore(prefix) {
            try warm(prefix: text)
            guard restore(prefix) else {
                try reset()
                return 0
            }
        }
        return prefix.count
    }

    private func restore(_ prefix: [Int32]) -> Bool {
        guard let snapshot, snapshot.tokens == prefix else { return false }
        pos = snapshot.pos
        for (name, array) in cacheArrays() {
            guard let data = snapshot.arrays[name] else { return false }
            if let rows = usedRows(array) {
                let heads = array.shape[1].intValue
                let width = array.shape[3].intValue
                guard data.count == heads * rows * width * 2 else { return false }
                array.withUnsafeMutableBufferPointer(ofType: Float16.self) { target, strides in
                    data.withUnsafeBytes { raw in
                        let source = raw.bindMemory(to: Float16.self).baseAddress!
                        for h in 0..<heads {
                            for r in 0..<rows {
                                (target.baseAddress! + h * strides[1] + r * strides[2]).update(from: source + (h * rows + r) * width, count: width)
                            }
                        }
                    }
                }
            } else {
                array.withUnsafeMutableBytes { raw, _ in
                    data.withUnsafeBytes { source in
                        raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: source.prefix(raw.count)))
                    }
                }
            }
        }
        return true
    }

    private func cacheArrays() -> [String: MLMultiArray] {
        var arrays: [String: MLMultiArray] = [:]
        for (layer, array) in keys { arrays["k\(layer)"] = array }
        for (layer, array) in values { arrays["v\(layer)"] = array }
        for (layer, array) in convs { arrays["c\(layer)"] = array }
        return arrays
    }

    private func advance(_ ids: [Int32], isCancelled: () -> Bool = { false }) throws -> MLMultiArray? {
        guard let bundle else { throw TextEngineError.notReady }
        guard !ids.isEmpty else { return nil }
        let block = bundle.shapes.prefill
        let canPrefill = block > 1 && parts.allSatisfy { $0.prefill != nil }
        let blocks = canPrefill ? CoreMLMath.passes(count: ids.count, prefill: block).filter { $0 == block }.count : 0
        var last: MLMultiArray?
        if blocks > 0 {
            last = try prefill(Array(ids[0..<blocks * block]), isCancelled: isCancelled)
        }
        for id in ids[(blocks * block)...] {
            if isCancelled() { throw CancellationError() }
            last = try autoreleasepool { try forward(id) }
        }
        return last
    }

    func step(_ token: Int32) throws -> [Float] {
        try autoreleasepool { try head(forward(token)) }
    }

    private func prefill(_ ids: [Int32], isCancelled: () -> Bool) throws -> MLMultiArray {
        guard let bundle else { throw TextEngineError.notReady }
        let block = bundle.shapes.prefill
        guard let set = inputs[block] else { throw TextEngineError.failed }
        guard pos + ids.count <= size else { throw TextEngineError.tooLong }
        let count = ids.count / block
        let hidden = try (0..<count).map { b in
            let array = try Self.array([1, block, bundle.spec.hiddenSize])
            embed(Array(ids[b * block..<(b + 1) * block]), into: array)
            return array
        }
        for part in parts {
            if isCancelled() { throw CancellationError() }
            guard let graph = part.prefill else { throw TextEngineError.failed }
            try autoreleasepool {
                let model = try model(graph)
                for b in 0..<count {
                    let start = pos + b * block
                    fill(set, seq: block, pos: start)
                    let out = try run(part, model: model, hidden: hidden[b], set: set, seq: block, pos: start)
                    Self.copy(out, into: hidden[b])
                }
            }
        }
        pos += ids.count
        return hidden[count - 1]
    }

    private func forward(_ id: Int32) throws -> MLMultiArray {
        guard bundle != nil, let set = inputs[1] else { throw TextEngineError.failed }
        guard pos + 1 <= size else { throw TextEngineError.tooLong }
        embed([id], into: set.hidden)
        fill(set, seq: 1, pos: pos)
        var hidden = set.hidden
        for part in parts {
            hidden = try run(part, model: part.decode, hidden: hidden, set: set, seq: 1, pos: pos)
        }
        pos += 1
        return hidden
    }

    private func fill(_ set: Inputs, seq: Int, pos: Int) {
        guard let bundle else { return }
        for (kind, inverse) in inverse {
            guard let cosArray = set.cos[kind], let sinArray = set.sin[kind], let maskArray = set.mask[kind] else { continue }
            let (cosines, sines) = CoreMLMath.rope(inverse: inverse, start: pos, count: seq)
            Self.write(cosines, into: cosArray)
            Self.write(sines, into: sinArray)
            let mask = CoreMLMath.mask(
                sliding: kind == CoreMLBundle.slidingAttention,
                length: bundle.cacheLength(kind, size: size),
                seq: seq,
                pos: pos,
                window: bundle.spec.slidingWindow
            )
            Self.write(mask, into: maskArray)
        }
    }

    private func run(_ part: Part, model: MLModel, hidden: MLMultiArray, set: Inputs, seq: Int, pos: Int) throws -> MLMultiArray {
        guard let bundle else { throw TextEngineError.notReady }
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
        let started = DispatchTime.now().uptimeNanoseconds
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: features))
        predictSeconds += Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
        for layer in part.attention {
            let length = bundle.cacheLength(bundle.kind(layer), size: size)
            try Self.store(out.featureValue(for: "k_\(layer)_out")?.multiArrayValue, into: keys[layer]!, pos: pos, length: length)
            try Self.store(out.featureValue(for: "v_\(layer)_out")?.multiArrayValue, into: values[layer]!, pos: pos, length: length)
        }
        for layer in part.conv {
            guard let state = out.featureValue(for: "conv_\(layer)_out")?.multiArrayValue else { throw TextEngineError.failed }
            Self.copy(state, into: convs[layer]!)
        }
        guard let next = out.featureValue(for: "hidden_out")?.multiArrayValue else { throw TextEngineError.failed }
        return next
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
        let loaded: MLModel
        do {
            loaded = try MLModel(contentsOf: compiled, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: compiled)
            try FileManager.default.moveItem(at: try Self.compile(package), to: compiled)
            loaded = try MLModel(contentsOf: compiled, configuration: configuration)
        }
        let footprint = EngineMetrics.memory().0
        Self.logger.notice("Loaded \(graph.file, privacy: .public) \(graph.function ?? "main", privacy: .public): footprint \(footprint) MB")
        return loaded
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
        let array = MLMultiArray(pixelBuffer: buffer, shape: [1, heads, rows, width].map { NSNumber(value: $0) })
        array.withUnsafeMutableBytes { raw, _ in
            _ = memset(raw.baseAddress!, 0, raw.count)
        }
        return array
    }

    private static func copyRows(_ source: MLMultiArray, into target: MLMultiArray, rows: Int) {
        let heads = source.shape[1].intValue
        let width = source.shape[3].intValue
        guard rows > 0 else { return }
        source.withUnsafeMutableBufferPointer(ofType: Float16.self) { from, s in
            target.withUnsafeMutableBufferPointer(ofType: Float16.self) { to, t in
                for h in 0..<heads {
                    for r in 0..<rows {
                        let a = h * s[1] + r * s[2]
                        let b = h * t[1] + r * t[2]
                        if s[3] == 1, t[3] == 1 {
                            (to.baseAddress! + b).update(from: from.baseAddress! + a, count: width)
                        } else {
                            for c in 0..<width {
                                to[b + c * t[3]] = from[a + c * s[3]]
                            }
                        }
                    }
                }
            }
        }
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
        prefix: String,
        full: (Int) -> String,
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
        let room = { (size: Int) in min(maxTokens, size / 4) }
        var reuse = cachedConversation == conversation && cachedTurns == turns && !cached.isEmpty
        var tokens: [Int32] = []
        var fresh: [Int32] = []
        if reuse {
            let added = try tokenize(next)
            let total = cached.count + added.count
            if total + room(context) > context, let bigger = sizes.first(where: { total + room($0) <= $0 }) {
                try resize(to: bigger)
            }
            if total + room(context) <= context {
                fresh = added
                tokens = cached + added
                metrics.reusedTokens = cached.count
            } else {
                reuse = false
            }
        }
        if !reuse {
            forgetAll()
            tokens = try tokenize(full(0))
            let count = tokens.count
            if count + room(context) > context {
                let bigger = sizes.first(where: { count + room($0) <= $0 }) ?? sizes[sizes.count - 1]
                if bigger > context {
                    pos = 0
                    try resize(to: bigger)
                }
            }
            var dropped = 0
            while tokens.count + room(context) > context, dropped + 2 <= turns {
                dropped += 2
                tokens = try tokenize(full(dropped))
            }
            guard tokens.count + room(context) <= context else {
                try reset()
                throw TextEngineError.tooLong
            }
            metrics.droppedTurns = dropped
            let reused = try begin(prefix: prefix, ids: tokens)
            fresh = Array(tokens[reused...])
            metrics.reusedTokens = reused
        }
        metrics.promptTokens = tokens.count
        cachedConversation = nil
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
        metrics.context = context
        return metrics
    }
}
