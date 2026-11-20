import Foundation
import os
import FirebaseAILogic

private let logger = Logger(subsystem: "com.materia.research.Materia", category: "AISummary")

actor AISummaryService {
    static let shared = AISummaryService()

    // Default cloud model: gemini-3.5-flash-lite via Gemini Developer API (free tier)
    private let modelName: String = "gemini-3.5-flash-lite"
    private var model: GenerativeModel?

    init() {
        // Intentionally lightweight: does not access FirebaseAI or create models during init.
    }

    private func getOrCreateModel() -> GenerativeModel {
        if let model {
            return model
        }

        // Ensure Firebase and App Check are configured before accessing FirebaseAI
        FirebaseConfigurator.configure()

        // Use Gemini Developer API text model supported by Firebase free tier (Backend.googleAI())
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let createdModel = ai.generativeModel(
            modelName: modelName,
            generationConfig: GenerationConfig(
                temperature: 0.1
            ),
            systemInstruction: ModelContent(
                role: "system",
                parts: """
                You are a rigorous, highly focused materials science and polymer engineering research assistant.
                Your task is to synthesize actual scientific paper abstracts retrieved from OpenAlex to directly answer the user's research question.

                Strict Synthesis Rules:
                1. Rely ONLY on the provided paper abstracts. Never extrapolate, hallucinate, or assume material properties, polymer formulations, test standards, or numerical values not explicitly stated.
                2. Do NOT summarize or re-narrate each paper abstract individually. Synthesize across papers to answer the question directly.
                3. Eliminate repetition completely: ensure the overview, findings, and gaps each convey distinct information without restating the same facts.
                4. Keep important scientific details accurate: preserve exact material names, polymer grades, temperatures, mechanical metrics (modulus, tensile strength, Tg), processing conditions, and units.
                5. Cite the supporting paper for each finding using the author and year or paper title (e.g., [Smith et al., 2023] or [Paper Title]).
                6. Avoid unnecessary explanations, filler language, and unsupported conclusions.

                Structure your response into EXACTLY these three labeled sections:

                ### OVERVIEW
                A concise 2–3 sentence direct answer to the research question based on the retrieved literature. Summarize the scientific consensus or primary mechanism without filler or introductory preamble.

                ### KEY FINDINGS
                3 to 5 concise, factual bullet points. Each bullet must state a distinct measurement, comparative trend, mechanism, or observed performance property, accompanied by a citation to the specific supporting paper. Do not include broad generalizations.

                ### RESEARCH GAPS
                2 to 3 concise bullet points identifying critical limitations, unaddressed processing/environmental variables, conflicting findings, or missing evidence in the provided literature (e.g., lack of long-term aging data, unverified scalability, untested temperature ranges).
                """
            ),
            requestOptions: RequestOptions(timeout: 30.0)
        )
        self.model = createdModel
        return createdModel
    }

    /// Tests the Firebase AI connection using an isolated "Hello" prompt.
    @discardableResult
    func testConnection() async throws -> (response: String, duration: TimeInterval) {
        let activeModel = getOrCreateModel()
        print("[AISummaryService] Sending isolated test 'Hello' prompt to model: \(modelName)...")
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let response = try await executeWithRetry(
                maxAttempts: 2,
                initialDelay: 1.0,
                maxDelay: 3.0,
                operationName: "Isolated 'Hello' prompt test"
            ) {
                try await activeModel.generateContent("Hello")
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            print("[AISummaryService] Isolated AI test prompt succeeded in \(String(format: "%.2f", elapsed))s! Response: \(text)")
            return (text, elapsed)
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let diagnostic = Self.diagnose(error)
            print("""
            ==================== AI TEST CONNECTION DIAGNOSTICS ====================
            Elapsed: \(String(format: "%.2f", elapsed))s
            \(diagnostic.technicalDetails)
            ========================================================================
            """)
            logger.error("\(diagnostic.technicalDetails, privacy: .public)")
            throw AISummaryError.generationFailed(
                userMessage: diagnostic.userMessage,
                technicalDetails: diagnostic.technicalDetails
            )
        }
    }

    /// Summarizes actual abstracts retrieved from OpenAlex with response time measurement.
    func summarize(question: String, papers: [ScientificPaper]) async throws -> AISummaryResult {
        let papersWithAbstracts = papers.filter {
            guard let abstract = $0.abstract else { return false }
            return !abstract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !papersWithAbstracts.isEmpty else {
            throw AISummaryError.noAbstractsAvailable
        }

        // Limit to the top 5 papers to stay within prompt limits and focus on highest relevance
        let selectedPapers = Array(papersWithAbstracts.prefix(5))

        var prompt = "Research Question: \(question)\n\n"
        prompt += "Retrieved Scientific Paper Abstracts from OpenAlex:\n"

        for (index, paper) in selectedPapers.enumerated() {
            let year = paper.publicationYear.map { " (\($0))" } ?? ""
            prompt += "\n--- Paper [\(index + 1)]: \"\(paper.title)\"\(year) ---\n"
            prompt += "Authors: \(paper.formattedAuthors)\n"
            if let journal = paper.journal {
                prompt += "Journal: \(journal)\n"
            }
            prompt += "Abstract:\n\(paper.abstract ?? "")\n"
        }

        prompt += "\nPlease synthesize the findings strictly following the three required sections: '### OVERVIEW', '### KEY FINDINGS', and '### RESEARCH GAPS'. Keep the summary concise, dense with scientific facts, free of repetition, and cite supporting papers for each key finding."
        let promptToSend = prompt

        let startTime = CFAbsoluteTimeGetCurrent()
        print("[AISummaryService] Initiating AI summary generation using \(selectedPapers.count) abstracts...")

        do {
            let activeModel = getOrCreateModel()
            let response = try await executeWithRetry(
                maxAttempts: 2,
                initialDelay: 1.0,
                maxDelay: 3.0,
                operationName: "Research Summary generation"
            ) {
                try await activeModel.generateContent(promptToSend)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw AISummaryError.emptyResponse
            }

            print("[AISummaryService] AI summary generated successfully in \(String(format: "%.2f", elapsed))s!")
            var result = parseSummary(text: text, paperCount: selectedPapers.count)
            result.responseTime = elapsed
            return result
        } catch let summaryError as AISummaryError {
            throw summaryError
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let diagnostic = Self.diagnose(error)
            print("""
            ==================== AI SUMMARY GENERATION ERROR ====================
            Elapsed: \(String(format: "%.2f", elapsed))s
            \(diagnostic.technicalDetails)
            =====================================================================
            """)
            logger.error("\(diagnostic.technicalDetails, privacy: .public)")
            throw AISummaryError.generationFailed(
                userMessage: diagnostic.userMessage,
                technicalDetails: diagnostic.technicalDetails
            )
        }
    }

    // MARK: - Retry Mechanism

    /// Bounded exponential-backoff retries for transient errors.
    /// Default to maximum 2 attempts to avoid unnecessary latency.
    private func executeWithRetry<T: Sendable>(
        maxAttempts: Int = 2,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 3.0,
        operationName: String,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var currentDelay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                let diagnostic = Self.diagnose(error)
                let isTransient = Self.isTransientError(diagnostic)

                if isTransient && attempt < maxAttempts {
                    let jitter = Double.random(in: 0.1...0.3)
                    let delay = min(currentDelay + jitter, maxDelay)
                    print("[AISummaryService] \(operationName) attempt \(attempt) failed with transient error (HTTP \(diagnostic.httpStatusCode?.description ?? "N/A")). Retrying in \(String(format: "%.1f", delay))s (attempt \(attempt + 1) of \(maxAttempts))...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    currentDelay *= 2.0
                } else {
                    if isTransient && attempt == maxAttempts {
                        print("[AISummaryService] \(operationName) failed after \(maxAttempts) attempts.")
                    }
                    throw error
                }
            }
        }

        throw AISummaryError.emptyResponse
    }

    private static func isTransientError(_ diagnostic: DiagnosticErrorInfo) -> Bool {
        if let status = diagnostic.httpStatusCode {
            // Transient HTTP statuses: 503 (Unavailable), 504 (Gateway Timeout / Deadline Exceeded), 502 (Bad Gateway), 429 (Rate Limit)
            return status == 503 || status == 504 || status == 502 || status == 429
        }
        let desc = diagnostic.technicalDetails.lowercased()
        return desc.contains("503") || desc.contains("deadline") || desc.contains("unavailable") || desc.contains("timed out")
    }

    private func parseSummary(text: String, paperCount: Int) -> AISummaryResult {
        let lines = text.components(separatedBy: .newlines)
        var currentSection: SummarySection? = nil
        var overviewLines: [String] = []
        var findingsLines: [String] = []
        var gapsLines: [String] = []

        enum SummarySection {
            case overview
            case keyFindings
            case researchGaps
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            let isHeaderLike = trimmed.hasPrefix("#") || trimmed.hasPrefix("**") || trimmed.hasPrefix("1.") || trimmed.hasPrefix("2.") || trimmed.hasPrefix("3.") || trimmed.hasSuffix(":")

            if lower.contains("overview") && isHeaderLike {
                currentSection = .overview
                continue
            } else if (lower.contains("key finding") || lower.contains("findings")) && isHeaderLike {
                currentSection = .keyFindings
                continue
            } else if (lower.contains("research gap") || lower.contains("gaps") || lower.contains("limitations") || lower.contains("missing evidence")) && isHeaderLike {
                currentSection = .researchGaps
                continue
            }

            switch currentSection {
            case .overview:
                overviewLines.append(line)
            case .keyFindings:
                findingsLines.append(line)
            case .researchGaps:
                gapsLines.append(line)
            case nil:
                // Pre-header content if any
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    overviewLines.append(line)
                }
            }
        }

        let overview = overviewLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let keyFindings = findingsLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let researchGaps = gapsLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // If the model followed the 3-section format:
        if !overview.isEmpty || !keyFindings.isEmpty || !researchGaps.isEmpty {
            let evidenceText: String
            if !overview.isEmpty && !keyFindings.isEmpty {
                evidenceText = """
                **Overview**
                \(overview)

                **Key Findings**
                \(keyFindings)
                """
            } else if !overview.isEmpty {
                evidenceText = overview
            } else {
                evidenceText = keyFindings
            }

            let interpretationText: String = !researchGaps.isEmpty
                ? "**Research Gaps**\n\(researchGaps)"
                : ""

            return AISummaryResult(
                overview: overview,
                keyFindings: keyFindings,
                researchGaps: researchGaps,
                evidenceText: evidenceText,
                interpretationText: interpretationText,
                abstractsUsedCount: paperCount
            )
        }

        // Backward-compatible fallback for legacy 2-section responses or freeform text
        let legacyEvidenceHeader = "### EVIDENCE FROM RETRIEVED PAPERS"
        let legacyInterpretationHeader = "### AI INTERPRETATION & SYNTHESIS"

        if text.contains(legacyEvidenceHeader) && text.contains(legacyInterpretationHeader) {
            let components = text.components(separatedBy: legacyInterpretationHeader)
            let evidencePart = components[0]
                .replacingOccurrences(of: legacyEvidenceHeader, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let interpretationPart = components.count > 1
                ? components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            return AISummaryResult(
                evidenceText: evidencePart,
                interpretationText: interpretationPart,
                abstractsUsedCount: paperCount
            )
        }

        return AISummaryResult(
            evidenceText: text.trimmingCharacters(in: .whitespacesAndNewlines),
            interpretationText: "",
            abstractsUsedCount: paperCount
        )
    }

    // MARK: - Diagnostics

    static func diagnose(_ error: Error) -> DiagnosticErrorInfo {
        var underlying: Error = error
        var httpStatus: Int? = nil

        if let generateError = error as? GenerateContentError {
            switch generateError {
            case .internalError(let inner):
                underlying = inner
            case .promptImageContentError(let inner):
                underlying = inner
            case .promptBlocked(let response):
                let reason = response.promptFeedback?.blockReason?.rawValue ?? "Safety"
                let userMsg = "The AI prompt was blocked by safety filters (\(reason))."
                let techMsg = "GenerateContentError.promptBlocked: blockReason=\(reason)"
                return DiagnosticErrorInfo(
                    userMessage: userMsg,
                    technicalDetails: techMsg,
                    httpStatusCode: nil,
                    domain: "FirebaseAILogic.GenerateContentError",
                    code: 2
                )
            case .responseStoppedEarly(let reason, _):
                let userMsg = "The AI response stopped early (\(reason.rawValue))."
                let techMsg = "GenerateContentError.responseStoppedEarly: reason=\(reason.rawValue)"
                return DiagnosticErrorInfo(
                    userMessage: userMsg,
                    technicalDetails: techMsg,
                    httpStatusCode: nil,
                    domain: "FirebaseAILogic.GenerateContentError",
                    code: 3
                )
            @unknown default:
                break
            }
        }

        let nsError = underlying as NSError
        let domain = nsError.domain
        let code = nsError.code
        let userInfo = nsError.userInfo

        // Extract HTTP status if code represents HTTP status code
        if (100...599).contains(code) {
            httpStatus = code
        }

        // Sanitize userInfo to avoid exposing API keys, debug tokens, or secrets
        var sanitizedUserInfo: [String: String] = [:]
        for (key, val) in userInfo {
            var str = "\(val)"
            if let keyRegex = try? NSRegularExpression(pattern: "AIza[0-9A-Za-z-_]{35}") {
                str = keyRegex.stringByReplacingMatches(
                    in: str,
                    range: NSRange(location: 0, length: str.utf16.count),
                    withTemplate: "AIza...[REDACTED]"
                )
            }
            if let uuidRegex = try? NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}") {
                str = uuidRegex.stringByReplacingMatches(
                    in: str,
                    range: NSRange(location: 0, length: str.utf16.count),
                    withTemplate: "[DEBUG-TOKEN-REDACTED]"
                )
            }
            sanitizedUserInfo[key] = str
        }

        let rawDescription = sanitizedUserInfo[NSLocalizedDescriptionKey] ?? nsError.localizedDescription

        // Determine user-friendly description
        var userMessage = rawDescription
        if let httpStatus {
            switch httpStatus {
            case 401:
                if rawDescription.localizedCaseInsensitiveContains("AppCheck") || rawDescription.localizedCaseInsensitiveContains("app check") {
                    userMessage = "App Check verification failed (HTTP 401). Ensure the Xcode debug token is registered in the Firebase Console."
                } else {
                    userMessage = "AI authentication failed (HTTP 401)."
                }
            case 403:
                if rawDescription.localizedCaseInsensitiveContains("SERVICE_DISABLED") || rawDescription.localizedCaseInsensitiveContains("firebasevertexai") {
                    userMessage = "Firebase AI API is not enabled in Firebase Console (HTTP 403). Please enable 'firebasevertexai.googleapis.com' in Google Cloud Console."
                } else if rawDescription.localizedCaseInsensitiveContains("AppCheck") || rawDescription.localizedCaseInsensitiveContains("app check") {
                    userMessage = "App Check rejected request (HTTP 403). Ensure debug token is added in Firebase Console."
                } else {
                    userMessage = "Access denied (HTTP 403): \(rawDescription)"
                }
            case 404:
                userMessage = "Model or endpoint not found (HTTP 404). Please verify model configuration."
            case 429:
                userMessage = "AI rate limit exceeded (HTTP 429). Please try again shortly."
            case 503:
                userMessage = "The AI service is temporarily unavailable (HTTP 503). Please try again in a few moments."
            case 504:
                userMessage = "The AI gateway timed out (HTTP 504). Please try again shortly."
            default:
                userMessage = "AI service error (HTTP \(httpStatus)): \(rawDescription)"
            }
        }

        let technicalDetails = """
        • Underlying Error Domain: \(domain)
        • Code: \(code)
        • HTTP Status: \(httpStatus.map(String.init) ?? "N/A")
        • Description: \(rawDescription)
        • UserInfo: \(sanitizedUserInfo)
        """

        return DiagnosticErrorInfo(
            userMessage: userMessage,
            technicalDetails: technicalDetails,
            httpStatusCode: httpStatus,
            domain: domain,
            code: code
        )
    }
}

struct DiagnosticErrorInfo: Sendable {
    let userMessage: String
    let technicalDetails: String
    let httpStatusCode: Int?
    let domain: String
    let code: Int
}

struct AISummaryResult: Hashable, Sendable {
    let overview: String
    let keyFindings: String
    let researchGaps: String
    let evidenceText: String
    let interpretationText: String
    let abstractsUsedCount: Int
    var responseTime: TimeInterval? = nil

    init(
        overview: String = "",
        keyFindings: String = "",
        researchGaps: String = "",
        evidenceText: String,
        interpretationText: String,
        abstractsUsedCount: Int,
        responseTime: TimeInterval? = nil
    ) {
        self.overview = overview
        self.keyFindings = keyFindings
        self.researchGaps = researchGaps
        self.evidenceText = evidenceText
        self.interpretationText = interpretationText
        self.abstractsUsedCount = abstractsUsedCount
        self.responseTime = responseTime
    }
}

enum AISummaryError: LocalizedError {
    case noAbstractsAvailable
    case emptyResponse
    case generationFailed(userMessage: String, technicalDetails: String)

    var errorDescription: String? {
        switch self {
        case .noAbstractsAvailable:
            return "No abstracts were available among the retrieved papers to summarize."
        case .emptyResponse:
            return "The AI model returned an empty summary. Please try again."
        case .generationFailed(let userMessage, _):
            return userMessage
        }
    }
}
