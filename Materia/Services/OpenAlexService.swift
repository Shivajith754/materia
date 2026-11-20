import Foundation
import os

private let logger = Logger(subsystem: "com.materia.research.Materia", category: "OpenAlexService")

struct OpenAlexResponse: Codable, Sendable {
    let results: [OpenAlexWork]
}

struct OpenAlexWork: Codable, Sendable {
    let id: String
    let doi: String?
    let title: String?
    let displayName: String?
    let publicationYear: Int?
    let citedByCount: Int?
    let primaryLocation: OpenAlexLocation?
    let openAccess: OpenAlexOpenAccess?
    let authorships: [OpenAlexAuthorship]?
    let abstractInvertedIndex: [String: [Int]]?

    enum CodingKeys: String, CodingKey {
        case id, doi, title
        case displayName = "display_name"
        case publicationYear = "publication_year"
        case citedByCount = "cited_by_count"
        case primaryLocation = "primary_location"
        case openAccess = "open_access"
        case authorships
        case abstractInvertedIndex = "abstract_inverted_index"
    }
}

struct OpenAlexLocation: Codable, Sendable {
    let landingPageUrl: String?
    let pdfUrl: String?
    let source: OpenAlexSource?

    enum CodingKeys: String, CodingKey {
        case landingPageUrl = "landing_page_url"
        case pdfUrl = "pdf_url"
        case source
    }
}

struct OpenAlexSource: Codable, Sendable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct OpenAlexOpenAccess: Codable, Sendable {
    let isOa: Bool?
    let oaUrl: String?

    enum CodingKeys: String, CodingKey {
        case isOa = "is_oa"
        case oaUrl = "oa_url"
    }
}

struct OpenAlexAuthorship: Codable, Sendable {
    let author: OpenAlexAuthor?
}

struct OpenAlexAuthor: Codable, Sendable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct OpenAlexErrorPayload: Codable, Sendable {
    let error: String?
    let message: String?
    let reason: String?
    let retryAfter: Double?
    let dailyRemainingUsd: Double?
}

public enum OpenAlexError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidApiKey(String?)
    case temporaryRateLimit(retryAfter: TimeInterval, message: String?)
    case dailyQuotaExceeded(resetSeconds: Int?, message: String?)
    case serverError(statusCode: Int)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Unable to construct a valid search URL."
        case .invalidApiKey(let message):
            if let msg = message, !msg.isEmpty {
                return msg
            }
            return "Invalid or unactivated OpenAlex API key. Please check OPENALEX_API_KEY in your .env file."
        case .temporaryRateLimit:
            return "OpenAlex search cluster is temporarily busy. Please wait a moment and try again."
        case .dailyQuotaExceeded(let resetSeconds, _):
            if let seconds = resetSeconds, seconds > 0 {
                let hours = seconds / 3600
                let minutes = (seconds % 3600) / 60
                return "OpenAlex daily request budget for this network reached (resets in \(hours)h \(minutes)m). Please try again later."
            }
            return "OpenAlex daily request budget for this network reached. Please try again later."
        case .serverError(let code):
            return "Unable to load papers from OpenAlex (Server status \(code))."
        case .decodingError:
            return "Unable to parse paper data from OpenAlex."
        }
    }
}

private struct CacheEntry: Sendable {
    let papers: [ScientificPaper]
    let timestamp: Date
}

actor OpenAlexService {
    static let shared = OpenAlexService()

    private let session: URLSession
    private let apiKeyProvider: @Sendable () -> String?
    private var cache: [String: CacheEntry] = [:]
    private var inFlightTasks: [String: Task<[ScientificPaper], Error>] = [:]
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping @Sendable () -> String? = { EnvironmentConfig.openAlexApiKey }
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    /// Searches OpenAlex for scientific works.
    /// - Checks 1-hour in-memory cache to eliminate duplicate network calls.
    /// - Deduplicates concurrent in-flight requests for the same query.
    /// - Automatically retries transient 429 throttling (up to 2 times), respecting Retry-After.
    func searchWorks(query: String, perPage: Int = 20) async throws -> [ScientificPaper] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let cacheKey = "\(trimmed.lowercased())__\(perPage)"

        // 1. Check in-memory 1-hour cache
        if let entry = cache[cacheKey] {
            let age = Date().timeIntervalSince(entry.timestamp)
            if age < cacheTTL {
                logger.debug("Cache hit for query '\(trimmed)' (age: \(String(format: "%.1f", age))s)")
                return entry.papers
            } else {
                cache.removeValue(forKey: cacheKey)
            }
        }

        // 2. Prevent duplicate in-flight requests
        if let existingTask = inFlightTasks[cacheKey] {
            logger.debug("Joining existing in-flight search task for query '\(trimmed)'")
            return try await existingTask.value
        }

        // 3. Create a single in-flight task for this query
        let searchTask = Task<[ScientificPaper], Error> {
            try await self.performSearchWithRetry(query: trimmed, perPage: perPage)
        }
        inFlightTasks[cacheKey] = searchTask

        do {
            let papers = try await searchTask.value
            inFlightTasks.removeValue(forKey: cacheKey)
            cache[cacheKey] = CacheEntry(papers: papers, timestamp: Date())
            return papers
        } catch {
            inFlightTasks.removeValue(forKey: cacheKey)
            throw error
        }
    }

    private func performSearchWithRetry(
        query: String,
        perPage: Int,
        maxRetries: Int = 2
    ) async throws -> [ScientificPaper] {
        var attempts = 0

        while true {
            attempts += 1
            do {
                return try await executeSingleSearch(query: query, perPage: perPage)
            } catch let error as OpenAlexError {
                switch error {
                case .temporaryRateLimit(let retryAfter, _):
                    if attempts <= maxRetries {
                        // Respect Retry-After header (bounded to [1, 15] seconds)
                        let delay = min(max(retryAfter, 1.0), 15.0)
                        logger.warning("OpenAlex 429 temporary throttle. Waiting \(String(format: "%.1f", delay))s before retry (attempt \(attempts)/\(maxRetries))...")
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    } else {
                        logger.error("OpenAlex temporary throttle exceeded maximum retries (\(maxRetries)).")
                        throw error
                    }
                case .dailyQuotaExceeded:
                    logger.error("OpenAlex actual daily budget exhausted. Not retrying.")
                    throw error
                default:
                    throw error
                }
            }
        }
    }

    private func executeSingleSearch(query: String, perPage: Int) async throws -> [ScientificPaper] {
        var components = URLComponents(string: "https://api.openalex.org/works")
        var queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per-page", value: String(min(max(perPage, 1), 50)))
        ]

        let apiKey = apiKeyProvider()
        if let key = apiKey, !key.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: key))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw OpenAlexError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MateriaApp/1.0 (mailto:support@materia.app)", forHTTPHeaderField: "User-Agent")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 20

        logger.debug("Dispatching OpenAlex request (key status: \(apiKey != nil ? "configured" : "none (anonymous)"))")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if (200...299).contains(httpResponse.statusCode) {
            do {
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(OpenAlexResponse.self, from: data)
                return decoded.results.map(ScientificPaper.init)
            } catch {
                throw OpenAlexError.decodingError(error.localizedDescription)
            }
        }

        if httpResponse.statusCode == 401 {
            let payload = try? JSONDecoder().decode(OpenAlexErrorPayload.self, from: data)
            let msg = payload?.message ?? "Invalid or unactivated API key."
            logger.error("OpenAlex API key authentication failed (HTTP 401): \(msg)")
            throw OpenAlexError.invalidApiKey(msg)
        }

        if httpResponse.statusCode == 429 {
            let payload = try? JSONDecoder().decode(OpenAlexErrorPayload.self, from: data)

            // Extract headers (case-insensitive in HTTPURLResponse)
            let retryHeaderStr = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let retryHeader = retryHeaderStr.flatMap { Double($0) }
            let remainingQuotaStr = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            let remainingUsdStr = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining-USD")
            let resetSecondsStr = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset")
            let resetSeconds = resetSecondsStr.flatMap { Int($0) }

            let isDailyBudgetExhausted = payload?.reason == "daily_budget" ||
                remainingQuotaStr == "0" ||
                remainingUsdStr == "0" ||
                payload?.dailyRemainingUsd == 0

            if isDailyBudgetExhausted {
                logger.error("Detected true OpenAlex daily budget exhaustion (reset in \(resetSeconds ?? 0)s)")
                throw OpenAlexError.dailyQuotaExceeded(
                    resetSeconds: resetSeconds,
                    message: payload?.message
                )
            } else {
                let retryDelay = payload?.retryAfter ?? retryHeader ?? 2.0
                logger.warning("Detected temporary OpenAlex 429 rate limit (retryAfter: \(retryDelay)s, reason: \(payload?.reason ?? "cluster_load"))")
                throw OpenAlexError.temporaryRateLimit(
                    retryAfter: retryDelay,
                    message: payload?.message
                )
            }
        }

        throw OpenAlexError.serverError(statusCode: httpResponse.statusCode)
    }

    /// Diagnostics & testing helpers
    func cachedEntryAge(for query: String, perPage: Int = 20) -> TimeInterval? {
        let cacheKey = "\(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())__\(perPage)"
        guard let entry = cache[cacheKey] else { return nil }
        return Date().timeIntervalSince(entry.timestamp)
    }

    func isCached(query: String, perPage: Int = 20) -> Bool {
        cachedEntryAge(for: query, perPage: perPage) != nil
    }

    func clearCache() {
        cache.removeAll()
    }
}
