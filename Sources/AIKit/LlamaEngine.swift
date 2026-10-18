import Foundation
import llama
import SuperNotesCore

/// A llama.cpp model and context, used only on its own serial queue. Loads a GGUF with every layer on the GPU,
/// builds the chat prompt with the model's own template and decodes greedily, handing out each piece of the
/// answer as it comes. Thinking models' `<think>…</think>` preamble is kept out of the answer.
public final class LlamaEngine: @unchecked Sendable {
    public let modelURL: URL
    private let queue = DispatchQueue(label: "supernotes.ai.llama", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var template: String?
    static let contextSize: UInt32 = 8192

    /// Backend set-up once per process; llama.cpp's own chatter stays out of the console except for errors.
    private static let backendReady: Void = {
        llama_log_set({ level, text, _ in
            guard level == GGML_LOG_LEVEL_ERROR, let text else { return }
            Log.ai.error("llama: \(String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)")
        }, nil)
        llama_backend_init()
    }()

    public init(modelURL: URL) { self.modelURL = modelURL }

    deinit { release() }

    public static var supportsGPUOffload: Bool { _ = backendReady; return llama_supports_gpu_offload() }

    /// Loads the model and makes a context. Synchronous on the engine's queue; a second call is a no-op.
    public func load() throws {
        try queue.sync { try loadNow() }
    }

    private func loadNow() throws {
        guard context == nil else { return }
        _ = Self.backendReady
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999
        guard let model = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw AIError.failed("Couldn't load \(modelURL.lastPathComponent)")
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = Self.contextSize
        contextParams.n_batch = 512
        contextParams.n_threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParams.n_threads_batch = contextParams.n_threads
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw AIError.failed("Couldn't start \(modelURL.lastPathComponent)")
        }
        self.model = model
        self.context = context
        vocab = llama_model_get_vocab(model)
        template = llama_model_chat_template(model, nil).map { String(cString: $0) }
    }

    public var isLoaded: Bool { queue.sync { context != nil } }

    public func unload() { queue.sync { release() } }

    private func release() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil; model = nil; vocab = nil; template = nil
    }

    // MARK: - Generation

    /// Answers `request`; pieces and the result come on the engine's queue. `cancel()` on the returned handle
    /// stops decoding at the next token.
    public func generate(_ request: AIRequest, onToken: @escaping @Sendable (String) -> Void,
                         completion: @escaping @Sendable (Result<String, AIError>) -> Void) -> AIGeneration {
        let generation = AIGeneration()
        queue.async { [self] in
            completion(Result { try generateNow(request, generation: generation, onToken: onToken) }
                .mapError { $0 as? AIError ?? .failed($0.localizedDescription) })
        }
        return generation
    }

    private func generateNow(_ request: AIRequest, generation: AIGeneration, onToken: @escaping @Sendable (String) -> Void) throws -> String {
        try loadNow()
        guard let context, let vocab else { throw AIError.failed("The model isn't loaded") }
        if generation.isCancelled { throw AIError.cancelled }
        let prompt = try chatPrompt(system: request.system, user: request.prompt)
        var tokens = tokenize(prompt, addSpecial: true)
        let maxTokens = max(1, request.maxTokens)
        guard tokens.count + maxTokens + 4 <= Int(Self.contextSize) else {
            throw AIError.failed("That's too long for the on-device model (\(tokens.count) tokens; it reads about "
                                 + "\(Int(Self.contextSize) - maxTokens) at once). Shorten the text or ask about part of it.")
        }

        llama_memory_clear(llama_get_memory(context), true)
        let batchSize = Int(llama_n_batch(context))
        var offset = 0
        while offset < tokens.count {
            let count = min(batchSize, tokens.count - offset)
            let status = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + offset, Int32(count)))
            }
            guard status == 0 else { throw AIError.failed("The model couldn't read the prompt (llama_decode \(status))") }
            offset += count
            if generation.isCancelled { throw AIError.cancelled }
        }

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw AIError.failed("Couldn't make a sampler")
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.1, 0, 0))
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        var bytes = UTF8Pieces()
        var filter = ThinkFilter()
        var answer = ""
        var generated = 0
        while generated < maxTokens {
            if generation.isCancelled { throw AIError.cancelled }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            let text = filter.feed(bytes.feed(piece(of: token, vocab: vocab)))
            if !text.isEmpty { answer += text; onToken(text) }
            generated += 1
            let status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard status == 0 else { break }   // 1: the context is full, which ends the answer
        }
        let rest = filter.flush(bytes.flush())
        if !rest.isEmpty { answer += rest; onToken(rest) }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.failed("The model returned an empty answer") }
        return trimmed
    }

    // MARK: - Tokens and templates

    func tokenize(_ text: String, addSpecial: Bool) -> [llama_token] {
        guard let vocab else { return [] }
        let utf8 = Array(text.utf8)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 16)
        var count = utf8.withUnsafeBufferPointer { bytes in
            llama_tokenize(vocab, bytes.baseAddress, Int32(bytes.count), &tokens, Int32(tokens.count), addSpecial, true)
        }
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = utf8.withUnsafeBufferPointer { bytes in
                llama_tokenize(vocab, bytes.baseAddress, Int32(bytes.count), &tokens, Int32(tokens.count), addSpecial, true)
            }
        }
        return count >= 0 ? Array(tokens.prefix(Int(count))) : []
    }

    private func piece(of token: llama_token, vocab: OpaquePointer) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        guard length > 0 else { return [] }
        return buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
    }

    /// The conversation as the model's chat template lays it out, ending with the assistant's turn. Thinking
    /// models get an empty think block, so they answer at once.
    private func chatPrompt(system: String, user: String) throws -> String {
        var messages = [(role: "user", content: user)]
        if !system.isEmpty { messages.insert((role: "system", content: system), at: 0) }
        let roles = messages.map { strdup($0.role) }, contents = messages.map { strdup($0.content) }
        defer { roles.forEach { free($0) }; contents.forEach { free($0) } }
        var chat = zip(roles, contents).map { llama_chat_message(role: $0, content: $1) }
        let source = template ?? "chatml"
        var buffer = [CChar](repeating: 0, count: user.utf8.count + system.utf8.count + 1024)
        var length = llama_chat_apply_template(source, &chat, chat.count, true, &buffer, Int32(buffer.count))
        if length < 0 {
            // An unknown template: ChatML is what the models in the catalog speak.
            length = llama_chat_apply_template("chatml", &chat, chat.count, true, &buffer, Int32(buffer.count))
        }
        if length > Int32(buffer.count) {
            buffer = [CChar](repeating: 0, count: Int(length) + 1)
            length = llama_chat_apply_template(source, &chat, chat.count, true, &buffer, Int32(buffer.count))
        }
        guard length >= 0 else { throw AIError.failed("Couldn't lay out the prompt for this model") }
        var prompt = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if source.contains("</think>") { prompt += "<think>\n\n</think>\n\n" }
        return prompt
    }
}

/// Joins token pieces into text without splitting a multi-byte character across two pieces.
public struct UTF8Pieces {
    private var pending: [UInt8] = []
    public init() {}

    /// The complete characters so far; a trailing partial sequence waits for the next piece.
    public mutating func feed(_ bytes: [UInt8]) -> String {
        pending += bytes
        let keep = Self.incompleteTail(pending)
        let ready = pending.prefix(pending.count - keep)
        pending.removeFirst(ready.count)
        return String(decoding: ready, as: UTF8.self)
    }

    public mutating func flush() -> String {
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }

    /// Bytes at the end that start a UTF-8 sequence the buffer doesn't finish.
    public static func incompleteTail(_ bytes: [UInt8]) -> Int {
        for back in 1...min(4, max(1, bytes.count)) where back <= bytes.count {
            let byte = bytes[bytes.count - back]
            if byte & 0xC0 == 0x80 { continue }                     // continuation byte: keep looking for the lead
            let needed = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            return needed > back ? back : 0
        }
        return 0
    }
}

/// Holds back a leading `<think>…</think>` block (what a thinking model writes before its answer) and lets
/// everything after it through.
public struct ThinkFilter {
    private var buffer = ""
    private var passed = false
    public init() {}
    private static let open = "<think>", close = "</think>"

    public mutating func feed(_ text: String) -> String {
        guard !passed else { return text }
        buffer += text
        let lead = buffer.drop { $0.isWhitespace }
        if lead.hasPrefix(Self.open) {
            guard let end = lead.range(of: Self.close) else { return "" }
            passed = true
            let rest = String(lead[end.upperBound...]).drop { $0 == "\n" }
            buffer = ""
            return String(rest)
        }
        if Self.open.hasPrefix(lead) { return "" }   // may still turn into "<think>"
        passed = true
        defer { buffer = "" }
        return buffer
    }

    /// What is still held at the end: an unclosed think block's text, without its tag.
    public mutating func flush(_ text: String) -> String {
        let held = feed(text)
        guard !passed else { return held }
        passed = true
        defer { buffer = "" }
        return buffer.replacingOccurrences(of: Self.open, with: "")
    }
}
