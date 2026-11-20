import Foundation
import Observation

@MainActor
@Observable
final class ResearchStore {
    private let openAlexService: OpenAlexService
    private var aiSummaryService: AISummaryService?
    private let suggestionService: AISuggestionService = .shared

    var queryText: String = ""

    init(
        openAlexService: OpenAlexService = .shared,
        aiSummaryService: AISummaryService? = nil
    ) {
        self.openAlexService = openAlexService
        self.aiSummaryService = aiSummaryService
    }

    private var summaryService: AISummaryService {
        if let aiSummaryService {
            return aiSummaryService
        }
        return AISummaryService.shared
    }

    var exampleQuestions: [ExampleQuestion] {
        ExampleQuestion.defaults
    }

    func searchPapers(query: String) async throws -> [ScientificPaper] {
        try await openAlexService.searchWorks(query: query)
    }

    func summarizePapers(question: String, papers: [ScientificPaper]) async throws -> AISummaryResult {
        try await summaryService.summarize(question: question, papers: papers)
    }

    func checkLocalAIStatus() async -> LocalAIStatus {
        await suggestionService.localAIStatus
    }

    func fetchSuggestions(for query: String, allowCloudFallback: Bool) async throws -> AISuggestionResult? {
        try await suggestionService.generateSuggestions(for: query, allowCloudFallback: allowCloudFallback)
    }
}
