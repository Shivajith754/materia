import Foundation
import os
import FirebaseAILogic

private let logger = Logger(subsystem: "com.materia.research.Materia", category: "AISuggestions")

public struct AISuggestionResult: Sendable, Equatable {
    public let suggestions: [String]
    public let modelUsed: String
    public let isOnDevice: Bool
    public let latency: TimeInterval

    public var badgeLabel: String {
        isOnDevice ? "On-Device Apple Intelligence" : "Cloud (\(modelUsed))"
    }
}

public enum LocalAIStatus: Sendable, Equatable {
    case available
    case unavailable(reason: String)
}

actor AISuggestionService {
    static let shared = AISuggestionService()

    private var cache: [String: AISuggestionResult] = [:]

    init() {
        // Lightweight initialization
    }

    /// Checks whether Apple Foundation Models are available on-device.
    var localAIStatus: LocalAIStatus {
        #if compiler(>=6.2.3)
        let systemModel = FirebaseAI.SystemLanguageModel.systemModel()
        switch systemModel.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(reason: "Device not eligible for Apple Foundation Models")
            case .appleIntelligenceNotEnabled:
                return .unavailable(reason: "Apple Intelligence not enabled in Settings")
            case .modelNotReady:
                return .unavailable(reason: "Apple Foundation Model not yet downloaded")
            case .unknown:
                return .unavailable(reason: "On-device model unavailable")
            @unknown default:
                return .unavailable(reason: "On-device model unavailable")
            }
        }
        #else
        return .unavailable(reason: "Platform does not support Foundation Models")
        #endif
    }

    var isLocalModelAvailable: Bool {
        if case .available = localAIStatus {
            return true
        }
        return false
    }

    /// Generates up to 3 specific polymer/materials science search query suggestions.
    /// Prefers on-device inference via Apple Foundation Models; falls back to cloud `gemini-3.5-flash-lite`
    /// only if cloud consent is granted.
    func generateSuggestions(
        for rawQuery: String,
        allowCloudFallback: Bool
    ) async throws -> AISuggestionResult? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            return nil
        }

        let cacheKey = trimmed.lowercased()
        if let cached = cache[cacheKey] {
            return cached
        }

        // Check availability: if local is unavailable and user has not consented to cloud, do not make cloud calls.
        let localAvailable = isLocalModelAvailable
        if !localAvailable && !allowCloudFallback {
            return nil
        }

        // Ensure Firebase is configured
        FirebaseConfigurator.configure()

        let ai = FirebaseAI.firebaseAI(backend: .googleAI())

        let prompt = """
        User research topic: "\(trimmed)"

        Suggest up to 3 more specific, refined, scientifically accurate research search queries for polymer science and materials engineering literature on OpenAlex.
        Return each suggestion on a separate line. Do not include numbers, bullet points, or commentary.
        """

        let instructions = """
        You are an expert materials science and polymer engineering research assistant. \
        Provide concise, highly relevant scientific search query suggestions that help researchers find specific papers.
        """

        let startTime = CFAbsoluteTimeGetCurrent()

        #if compiler(>=6.2.3)
        let session: GenerativeModelSession
        if allowCloudFallback {
            // Hybrid SDK: Primary on-device Apple Foundation Model with fallback to gemini-3.5-flash-lite
            let hybridProvider = HybridModelProvider.hybridModel(
                primary: FirebaseAI.SystemLanguageModel.systemModel(useCase: .general),
                secondary: GeminiModelProvider.geminiModel(name: "gemini-3.5-flash-lite")
            )
            session = ai.generativeModelSession(
                model: hybridProvider,
                instructions: instructions
            )
        } else {
            // Local on-device only
            let systemModel = FirebaseAI.SystemLanguageModel.systemModel(useCase: .general)
            session = ai.generativeModelSession(
                model: systemModel,
                instructions: instructions
            )
        }

        let response = try await session.respond(to: prompt)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        let rawText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelVersion = response.rawResponse.modelVersion
        let isOnDevice = modelVersion.contains("apple-foundation-models") || modelVersion.contains("system-language-model")

        let lines = rawText
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "^[0-9]+[\\.\\)]\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "^[\\*\\-\\•]\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && $0.count > 3 }

        let suggestions = Array(lines.prefix(3))
        guard !suggestions.isEmpty else {
            return nil
        }

        let result = AISuggestionResult(
            suggestions: suggestions,
            modelUsed: modelVersion,
            isOnDevice: isOnDevice,
            latency: elapsed
        )

        cache[cacheKey] = result
        print("[AISuggestionService] Generated \(suggestions.count) suggestions in \(String(format: "%.2f", elapsed))s using: \(result.badgeLabel)")
        return result
        #else
        return nil
        #endif
    }

    /// For testing and diagnostics: verifies the Firebase AI Logic hybrid fallback mechanics by forcing
    /// the primary session to fail, triggering the automatic fallback to gemini-3.5-flash-lite.
    func testHybridCloudFallback(for rawQuery: String) async throws -> AISuggestionResult? {
        #if compiler(>=6.2.3)
        FirebaseConfigurator.configure()
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let prompt = """
        User research topic: "\(rawQuery)"

        Suggest up to 3 more specific, refined, scientifically accurate research search queries for polymer science and materials engineering literature on OpenAlex.
        Return each suggestion on a separate line. Do not include numbers, bullet points, or commentary.
        """
        let instructions = "You are an expert materials science and polymer engineering research assistant."
        let startTime = CFAbsoluteTimeGetCurrent()

        let hybridProvider = HybridModelProvider.hybridModel(
            primary: GeminiModelProvider.geminiModel(name: "gemini-nonexistent-to-trigger-fallback"),
            secondary: GeminiModelProvider.geminiModel(name: "gemini-3.5-flash-lite")
        )
        let session = ai.generativeModelSession(
            model: hybridProvider,
            instructions: instructions
        )

        let response = try await session.respond(to: prompt)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let rawText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelVersion = response.rawResponse.modelVersion
        let isOnDevice = modelVersion.contains("apple-foundation-models") || modelVersion.contains("system-language-model")

        let lines = rawText
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "^[0-9]+[\\.\\)]\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "^[\\*\\-\\•]\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && $0.count > 3 }

        let suggestions = Array(lines.prefix(3))
        guard !suggestions.isEmpty else { return nil }

        return AISuggestionResult(
            suggestions: suggestions,
            modelUsed: modelVersion,
            isOnDevice: isOnDevice,
            latency: elapsed
        )
        #else
        return nil
        #endif
    }
}
