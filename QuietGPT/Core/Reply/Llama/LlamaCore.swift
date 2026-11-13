import Foundation
import llama

nonisolated struct LlamaMetrics: Sendable {
    var loadSeconds: Double?
    var promptTokens = 0
    var reusedTokens = 0
    var prefillSeconds = 0.0
    var firstTokenSeconds: Double?
    var generatedTokens = 0
    var decodeSeconds = 0.0
    var footprintMB = 0
    var peakMB = 0
    var thermal = ""

    var summary: String {
        let load = loadSeconds.map { String(format: "load %.2f s · ", $0) } ?? ""
        let prefillRate = prefillSeconds > 0 ? Double(promptTokens - reusedTokens) / prefillSeconds : 0
        let decodeRate = decodeSeconds > 0 ? Double(generatedTokens) / decodeSeconds : 0
        let first = firstTokenSeconds.map { String(format: "%.2f s", $0) } ?? "-"
        return load
            + "prompt \(promptTokens) tok (reused \(reusedTokens)) · "
            + String(format: "prefill %.2f s (%.0f tok/s) · ", prefillSeconds, prefillRate)
            + "first token \(first) · "
            + String(format: "decode %d tok at %.1f tok/s · ", generatedTokens, decodeRate)
            + "memory \(footprintMB) MB, peak \(peakMB) MB · thermal \(thermal)"
    }
}

nonisolated final class LlamaCore: @unchecked Sendable {
    static let contextSize: UInt32 = 8192
    private static let batchSize = 512
    private static let backend: Void = llama_backend_init()

    let queue = DispatchQueue(label: "QuietGPT.llama", qos: .userInitiated)
    private let path: String
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var cached: [llama_token] = []
    private var cachedConversation: UUID?
    private var cachedTurns = -1

    init(path: String) {
        self.path = path
    }

    deinit {
        unload()
    }

    func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        vocab = nil
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

    func generate(
        conversation: UUID,
        turns: Int,
        full: String,
        next: String,
        maxTokens: Int,
        isCancelled: () -> Bool,
        yield: (String) -> Void
    ) throws -> LlamaMetrics {
        var metrics = LlamaMetrics()
        let loadStart = Date()
        if context == nil {
            try load()
            metrics.loadSeconds = Date().timeIntervalSince(loadStart)
        }
        guard let context, let vocab else { throw TextEngineError.notReady }

        let reuse = cachedConversation == conversation && cachedTurns == turns && !cached.isEmpty
        var tokens: [llama_token]
        var fresh: [llama_token]
        if reuse {
            fresh = tokenize(next)
            tokens = cached + fresh
            metrics.reusedTokens = cached.count
        } else {
            llama_memory_clear(llama_get_memory(context), true)
            forgetAll()
            fresh = tokenize(full)
            tokens = fresh
        }
        metrics.promptTokens = tokens.count
        guard tokens.count + maxTokens <= Int(Self.contextSize) else {
            llama_memory_clear(llama_get_memory(context), true)
            forgetAll()
            throw TextEngineError.tooLong
        }

        cachedConversation = nil
        let prefillStart = Date()
        var offset = 0
        while offset < fresh.count {
            if isCancelled() { throw CancellationError() }
            let count = min(Self.batchSize, fresh.count - offset)
            let status = fresh.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + offset, Int32(count)))
            }
            guard status == 0 else {
                llama_memory_clear(llama_get_memory(context), true)
                throw TextEngineError.failed
            }
            offset += count
        }
        metrics.prefillSeconds = Date().timeIntervalSince(prefillStart)

        let sampler = Self.makeSampler(vocab: vocab)
        defer { llama_sampler_free(sampler) }
        var bytes: [UInt8] = []
        let decodeStart = Date()
        while metrics.generatedTokens < maxTokens, !isCancelled() {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(token)
            tokens.append(token)
            metrics.generatedTokens += 1
            if metrics.firstTokenSeconds == nil {
                metrics.firstTokenSeconds = Date().timeIntervalSince(prefillStart)
            }
            if let text = String(validating: bytes, as: UTF8.self) {
                yield(text)
            }
            guard llama_decode(context, llama_batch_get_one(&token, 1)) == 0 else {
                llama_memory_clear(llama_get_memory(context), true)
                throw TextEngineError.failed
            }
        }
        metrics.decodeSeconds = Date().timeIntervalSince(decodeStart)

        cached = tokens
        cachedConversation = conversation
        cachedTurns = turns + 2
        (metrics.footprintMB, metrics.peakMB) = Self.memory()
        metrics.thermal = Self.thermal()
        return metrics
    }

    private func load() throws {
        _ = Self.backend
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999
        guard let model = llama_model_load_from_file(path, modelParams) else { throw TextEngineError.notReady }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = Self.contextSize
        contextParams.n_batch = UInt32(Self.batchSize)
        contextParams.n_ubatch = UInt32(Self.batchSize)
        let threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw TextEngineError.failed
        }
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
    }

    private func tokenize(_ text: String) -> [llama_token] {
        let utf8 = Array(text.utf8CString)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 8)
        var count = llama_tokenize(vocab, utf8, Int32(utf8.count - 1), &tokens, Int32(tokens.count), false, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, utf8, Int32(utf8.count - 1), &tokens, Int32(tokens.count), false, true)
        }
        return Array(tokens.prefix(Int(max(0, count))))
    }

    private func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        return buffer.prefix(Int(max(0, count))).map { UInt8(bitPattern: $0) }
    }

    private static func makeSampler(vocab: OpaquePointer) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.1, 0, 0))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(50))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_min_p(0.05, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.1))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        return chain
    }

    static func memory() -> (Int, Int) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (Int(info.phys_footprint >> 20), Int(info.ledger_phys_footprint_peak >> 20))
    }

    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
