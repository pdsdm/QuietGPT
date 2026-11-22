#if DEBUG
import Foundation
import llama

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
    ) throws -> EngineMetrics {
        var metrics = EngineMetrics()
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
            fresh = LlamaVocab.tokenize(next, vocab: vocab)
            tokens = cached + fresh
            metrics.reusedTokens = cached.count
        } else {
            llama_memory_clear(llama_get_memory(context), true)
            forgetAll()
            fresh = LlamaVocab.tokenize(full, vocab: vocab)
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
            bytes += LlamaVocab.piece(token, vocab: vocab)
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
        (metrics.footprintMB, metrics.peakMB) = EngineMetrics.memory()
        metrics.thermal = EngineMetrics.thermal()
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
}
#endif
