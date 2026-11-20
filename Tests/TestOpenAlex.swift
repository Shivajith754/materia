import Foundation

// MARK: - Mock URL Protocol for Unit Testing Network & Auth Behavior

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        requestHandler = nil
        capturedRequests = []
    }

    static func record(request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests.append(request)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.record(request: request)
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Sample Fixtures

let sampleOpenAlexJSON = """
{
  "results": [
    {
      "id": "https://openalex.org/W1234567890",
      "doi": "https://doi.org/10.1000/182",
      "title": "Novel Polycarbonate Synthesis and Mechanical Characterization",
      "display_name": "Novel Polycarbonate Synthesis and Mechanical Characterization",
      "publication_year": 2024,
      "cited_by_count": 42,
      "primary_location": {
        "landing_page_url": "https://doi.org/10.1000/182",
        "pdf_url": "https://example.com/paper.pdf",
        "source": {
          "display_name": "Journal of Polymer Science"
        }
      },
      "open_access": {
        "is_oa": true,
        "oa_url": "https://example.com/paper.pdf"
      },
      "authorships": [
        { "author": { "display_name": "Dr. Marie Curie" } },
        { "author": { "display_name": "Dr. Pierre Curie" } }
      ],
      "abstract_inverted_index": {
        "Polycarbonate": [0],
        "exhibits": [1],
        "remarkable": [2],
        "impact": [3],
        "resistance": [4]
      }
    }
  ]
}
""".data(using: .utf8)!

let error401JSON = """
{
  "error": "Invalid or missing API key",
  "message": "API key not found. Get a free key at https://openalex.org/settings/api-key."
}
""".data(using: .utf8)!

let error429DailyQuotaJSON = """
{
  "error": "Daily request budget reached",
  "message": "Your IP or key has exceeded the daily limit of 100,000 requests.",
  "reason": "daily_budget",
  "daily_remaining_usd": 0
}
""".data(using: .utf8)!

let error429ClusterLoadJSON = """
{
  "error": "Temporary Rate Limit",
  "message": "Cluster load high. Please retry after delay.",
  "reason": "cluster_load",
  "retry_after": 0.05
}
""".data(using: .utf8)!

// MARK: - Test Suite Runner

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

func runAllTests() async {
    print("==================================================")
    print("🧪 Matéria: Running OpenAlex API Key & Service Test Suite")
    print("==================================================")

    var passed = 0
    var failed = 0

    func assertTest(_ condition: Bool, _ name: String) {
        if condition {
            print("  ✅ PASS: \(name)")
            passed += 1
        } else {
            print("  ❌ FAIL: \(name)")
            failed += 1
        }
    }

    // ----------------------------------------------------
    // Test 1: .env File Loading & Immutable Cache
    // ----------------------------------------------------
    print("\n--- Test Group 1: EnvironmentConfig & Immutable .env Loading ---")
    let rawKey = EnvironmentConfig.rawOpenAlexApiKey
    assertTest(rawKey != nil, "rawOpenAlexApiKey loaded from .env (found: '\(rawKey ?? "nil")')")

    // Verify placeholder detection logic
    assertTest(EnvironmentConfig.isPlaceholderKey("your_openalex_api_key_here"), "isPlaceholderKey detects 'your_openalex_api_key_here'")
    assertTest(EnvironmentConfig.isPlaceholderKey("your_key_here"), "isPlaceholderKey detects 'your_key_here'")
    assertTest(EnvironmentConfig.isPlaceholderKey("<your_key>"), "isPlaceholderKey detects '<your_key>'")
    assertTest(!EnvironmentConfig.isPlaceholderKey("dummy_real_format_key_12345"), "isPlaceholderKey returns false for real key")

    // Active key & masking
    if EnvironmentConfig.hasPlaceholderApiKey {
        assertTest(EnvironmentConfig.openAlexApiKey == nil, "openAlexApiKey returns nil when placeholder is configured")
        assertTest(EnvironmentConfig.sanitizedKeyPreview.contains("placeholder"), "sanitizedKeyPreview reports placeholder state")
    } else {
        assertTest(EnvironmentConfig.hasOpenAlexApiKey, "hasOpenAlexApiKey is true with active user key")
        assertTest(EnvironmentConfig.openAlexApiKey != nil, "openAlexApiKey returns configured key")
        assertTest(EnvironmentConfig.sanitizedKeyPreview.contains("••••"), "sanitizedKeyPreview masks secret with bullets")
    }

    // Test runtime process environment override priority
    setenv("OPENALEX_API_KEY", "019847291a2b3c4d", 1)
    assertTest(EnvironmentConfig.hasOpenAlexApiKey, "hasOpenAlexApiKey is true when real key is provided via env")
    assertTest(EnvironmentConfig.openAlexApiKey == "019847291a2b3c4d", "openAlexApiKey correctly resolves override key")
    assertTest(EnvironmentConfig.sanitizedKeyPreview == "configured (••••3c4d)", "sanitizedKeyPreview masks override key: '\(EnvironmentConfig.sanitizedKeyPreview)'")

    // Restore process environment back to .env state
    unsetenv("OPENALEX_API_KEY")
    assertTest(EnvironmentConfig.rawOpenAlexApiKey == rawKey, "Reverted back to .env state successfully")

    // ----------------------------------------------------
    // Test 2: Active API Key Injection in Requests
    // ----------------------------------------------------
    print("\n--- Test Group 2: OpenAlexService with Active API Key ---")
    MockURLProtocol.reset()
    MockURLProtocol.requestHandler = { req in
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (resp, sampleOpenAlexJSON)
    }

    let testApiKey = "test_actual_openalex_key_98765"
    let mockSession = makeMockSession()
    let serviceWithKey = OpenAlexService(session: mockSession, apiKeyProvider: { testApiKey })

    do {
        let papers = try await serviceWithKey.searchWorks(query: "polycarbonate")
        assertTest(!papers.isEmpty, "Search returned parsed ScientificPaper models")
        assertTest(papers.first?.title == "Novel Polycarbonate Synthesis and Mechanical Characterization", "Parsed paper title matches fixture")
        assertTest(papers.first?.authors.contains("Dr. Marie Curie") == true, "Parsed author Marie Curie")
        assertTest(papers.first?.abstract == "Polycarbonate exhibits remarkable impact resistance", "Reconstructed inverted index abstract")

        let lastReq = MockURLProtocol.capturedRequests.last!
        let urlString = lastReq.url?.absoluteString ?? ""
        let authHeader = lastReq.value(forHTTPHeaderField: "Authorization") ?? ""
        let userAgent = lastReq.value(forHTTPHeaderField: "User-Agent") ?? ""

        assertTest(urlString.contains("api_key=\(testApiKey)"), "URL contains 'api_key=\(testApiKey)' query param")
        assertTest(authHeader == "Bearer \(testApiKey)", "HTTP Header contains 'Authorization: Bearer \(testApiKey)'")
        assertTest(userAgent.contains("MateriaApp"), "HTTP Header contains MateriaApp User-Agent")
    } catch {
        assertTest(false, "serviceWithKey threw unexpected error: \(error)")
    }

    // ----------------------------------------------------
    // Test 3: Anonymous / No-Key Mode
    // ----------------------------------------------------
    print("\n--- Test Group 3: OpenAlexService in Anonymous Mode (No Key) ---")
    MockURLProtocol.reset()
    MockURLProtocol.requestHandler = { req in
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (resp, sampleOpenAlexJSON)
    }

    let serviceAnonymous = OpenAlexService(session: mockSession, apiKeyProvider: { nil })
    do {
        _ = try await serviceAnonymous.searchWorks(query: "graphene polymers")
        let lastReq = MockURLProtocol.capturedRequests.last!
        let urlString = lastReq.url?.absoluteString ?? ""
        let authHeader = lastReq.value(forHTTPHeaderField: "Authorization")

        assertTest(!urlString.contains("api_key="), "Anonymous request does not include 'api_key' param")
        assertTest(authHeader == nil, "Anonymous request does not include 'Authorization' header")
    } catch {
        assertTest(false, "serviceAnonymous threw unexpected error: \(error)")
    }

    // ----------------------------------------------------
    // Test 4: Preserved 1-Hour In-Memory Cache
    // ----------------------------------------------------
    print("\n--- Test Group 4: Preserved 1-Hour Caching Logic ---")
    MockURLProtocol.reset()
    var networkCallCount = 0
    MockURLProtocol.requestHandler = { req in
        networkCallCount += 1
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (resp, sampleOpenAlexJSON)
    }

    let cacheService = OpenAlexService(session: mockSession, apiKeyProvider: { "cached_key" })
    do {
        // Call 1
        _ = try await cacheService.searchWorks(query: "carbon fiber")
        assertTest(networkCallCount == 1, "First search query executed 1 network request")
        assertTest(await cacheService.isCached(query: "carbon fiber"), "Query is stored in in-memory cache")

        // Call 2 (identical query)
        _ = try await cacheService.searchWorks(query: "carbon fiber")
        assertTest(networkCallCount == 1, "Second search query served from cache (network calls remained 1)")

        // Age helper
        let age = await cacheService.cachedEntryAge(for: "carbon fiber")
        assertTest(age != nil && age! < 5.0, "cachedEntryAge returned valid age (< 5s)")

        // Clear cache
        await cacheService.clearCache()
        assertTest(await !cacheService.isCached(query: "carbon fiber"), "clearCache() emptied cache")
    } catch {
        assertTest(false, "Caching test failed with error: \(error)")
    }

    // ----------------------------------------------------
    // Test 5: In-Flight Task Deduplication
    // ----------------------------------------------------
    print("\n--- Test Group 5: In-Flight Request Deduplication ---")
    MockURLProtocol.reset()
    var inflightNetCount = 0
    MockURLProtocol.requestHandler = { req in
        inflightNetCount += 1
        Thread.sleep(forTimeInterval: 0.1) // simulate slight network latency
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (resp, sampleOpenAlexJSON)
    }

    let dedupService = OpenAlexService(session: mockSession, apiKeyProvider: { "dedup_key" })
    async let reqA = dedupService.searchWorks(query: "simultaneous query")
    async let reqB = dedupService.searchWorks(query: "simultaneous query")

    do {
        let (resA, resB) = try await (reqA, reqB)
        assertTest(resA.count == resB.count, "Both concurrent tasks returned same results")
        assertTest(inflightNetCount == 1, "Concurrent tasks coalesced into a single network request")
    } catch {
        assertTest(false, "In-flight deduplication failed: \(error)")
    }

    // ----------------------------------------------------
    // Test 6: Rate Limiting - 429 Temporary Throttle Retry
    // ----------------------------------------------------
    print("\n--- Test Group 6: Rate Limit - 429 Throttle Retry ---")
    MockURLProtocol.reset()
    var throttleAttempts = 0
    MockURLProtocol.requestHandler = { req in
        throttleAttempts += 1
        if throttleAttempts == 1 {
            // First attempt: return 429 cluster load
            let headers = ["Retry-After": "0.05"]
            let resp = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: headers)!
            return (resp, error429ClusterLoadJSON)
        } else {
            // Second attempt: succeeds
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, sampleOpenAlexJSON)
        }
    }

    let retryService = OpenAlexService(session: mockSession, apiKeyProvider: { "retry_key" })
    do {
        let papers = try await retryService.searchWorks(query: "aerogel")
        assertTest(!papers.isEmpty, "Search succeeded after automatic retry")
        assertTest(throttleAttempts == 2, "Automatic retry triggered (attempts count: 2)")
    } catch {
        assertTest(false, "Retry test failed: \(error)")
    }

    // ----------------------------------------------------
    // Test 7: Rate Limiting - 429 Daily Quota Exhausted (No Retry)
    // ----------------------------------------------------
    print("\n--- Test Group 7: Rate Limit - 429 Daily Budget Exhaustion ---")
    MockURLProtocol.reset()
    var dailyAttempts = 0
    MockURLProtocol.requestHandler = { req in
        dailyAttempts += 1
        let headers = [
            "X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": "7200"
        ]
        let resp = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: headers)!
        return (resp, error429DailyQuotaJSON)
    }

    let quotaService = OpenAlexService(session: mockSession, apiKeyProvider: { "quota_key" })
    do {
        _ = try await quotaService.searchWorks(query: "exhausted budget")
        assertTest(false, "Expected dailyQuotaExceeded error, but call succeeded")
    } catch let error as OpenAlexError {
        switch error {
        case .dailyQuotaExceeded(let resetSeconds, _):
            assertTest(true, "Caught OpenAlexError.dailyQuotaExceeded (resetSeconds: \(resetSeconds ?? 0))")
            assertTest(dailyAttempts == 1, "Did not wastefully retry when daily budget was exhausted (attempts: 1)")
        default:
            assertTest(false, "Caught wrong OpenAlexError: \(error)")
        }
    } catch {
        assertTest(false, "Caught wrong error type: \(error)")
    }

    // ----------------------------------------------------
    // Test 8: Authentication - HTTP 401 Invalid API Key
    // ----------------------------------------------------
    print("\n--- Test Group 8: HTTP 401 Invalid API Key Handling ---")
    MockURLProtocol.reset()
    MockURLProtocol.requestHandler = { req in
        let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        return (resp, error401JSON)
    }

    let badKeyService = OpenAlexService(session: mockSession, apiKeyProvider: { "bad_invalid_key" })
    do {
        _ = try await badKeyService.searchWorks(query: "bioplastics")
        assertTest(false, "Expected invalidApiKey error, but call succeeded")
    } catch let error as OpenAlexError {
        switch error {
        case .invalidApiKey(let msg):
            assertTest(true, "Caught OpenAlexError.invalidApiKey: '\(msg ?? "")'")
        default:
            assertTest(false, "Caught unexpected OpenAlexError: \(error)")
        }
    } catch {
        assertTest(false, "Caught wrong error type: \(error)")
    }

    // ----------------------------------------------------
    // Summary
    // ----------------------------------------------------
    print("\n==================================================")
    print("📊 Test Summary: \(passed) passed, \(failed) failed")
    print("==================================================")
    if failed > 0 {
        exit(1)
    }
}

@main
struct TestRunner {
    static func main() async {
        await runAllTests()
    }
}
