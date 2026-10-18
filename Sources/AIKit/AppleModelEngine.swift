import Foundation
import SuperNotesCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (FoundationModels, macOS 26). Where the SDK or the Mac lacks it, `isAvailable` is
/// false and nothing else is called.
enum AppleModelEngine {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Why the model can't answer on this Mac, in Apple's words where it has them.
    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return "This Mac can't run Apple's on-device model."
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings to use Apple's on-device model."
                case .modelNotReady: return "Apple's on-device model is still being set up by macOS; try again in a little while."
                @unknown default: return "Apple's on-device model isn't available right now."
                }
            }
        }
        #endif
        return "Apple's on-device model needs macOS 26 or later."
    }

    /// Answers `request`, streaming the answer as it grows. Pieces and the result arrive on arbitrary threads.
    static func generate(_ request: AIRequest, onToken: @escaping @Sendable (String) -> Void,
                         completion: @escaping @Sendable (Result<String, AIError>) -> Void) -> AIGeneration {
        let generation = AIGeneration()
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let task = Task.detached {
                do {
                    let session = LanguageModelSession(instructions: request.system.isEmpty ? nil : request.system)
                    let options = GenerationOptions(maximumResponseTokens: request.maxTokens)
                    var answer = ""
                    for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                        try Task.checkCancellation()
                        let content = snapshot.content
                        if content.hasPrefix(answer) { onToken(String(content.dropFirst(answer.count))) } else { onToken(content) }
                        answer = content
                    }
                    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(trimmed.isEmpty ? .failure(.failed("Apple's model returned an empty answer")) : .success(trimmed))
                } catch is CancellationError {
                    completion(.failure(.cancelled))
                } catch {
                    completion(.failure(generation.isCancelled ? .cancelled : .failed(error.localizedDescription)))
                }
            }
            generation.onCancel { task.cancel() }
            return generation
        }
        #endif
        completion(.failure(.unavailable(unavailableReason)))
        return generation
    }
}
