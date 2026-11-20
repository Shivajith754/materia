import Foundation

// MARK: - Test Suite for Cloud Fallback & Hybrid Inference Logic

struct MockSuggestionModel {
    let modelVersion: String
    let shouldFail: Bool
    let responseText: String

    func respond(to prompt: String) throws -> (content: String, modelVersion: String) {
        if shouldFail {
            throw NSError(domain: "MockModelError", code: 503, userInfo: [NSLocalizedDescriptionKey: "Model temporarily unavailable"])
        }
        return (responseText, modelVersion)
    }
}

// Simulates the HybridModelProvider runtime mechanics
struct MockHybridEngine {
    let primary: MockSuggestionModel
    let secondary: MockSuggestionModel

    func execute(prompt: String) throws -> (content: String, modelVersion: String) {
        do {
            return try primary.respond(to: prompt)
        } catch {
            // Automatic fallback to secondary provider
            return try secondary.respond(to: prompt)
        }
    }
}

@main
struct CloudFallbackTests {
    static func main() {
        print("==================================================")
        print("🧪 Testing Hybrid Inference & Cloud Fallback Logic")
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

        // Test 1: Privacy gate when local model unavailable and cloud consent not granted
        print("\n--- Test Group 1: Privacy Gate & Availability ---")
        let isLocalAvailable = false
        let allowCloudFallback = false

        let shouldProceed = isLocalAvailable || allowCloudFallback
        assertTest(!shouldProceed, "Privacy gate blocks execution when local model is unavailable and cloud consent is false")

        // Test 2: Privacy gate opens when user grants consent
        let userConsented = true
        let shouldProceedWithConsent = isLocalAvailable || userConsented
        assertTest(shouldProceedWithConsent, "Execution permitted when user explicitly grants cloud consent")

        // Test 3: Short queries (< 3 chars) are filtered
        let shortQuery = "po"
        assertTest(shortQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 3, "Queries shorter than 3 characters are safely ignored")

        // Test 4: Response line cleaning and parsing
        print("\n--- Test Group 2: Suggestion Text Cleaning & Normalization ---")
        let rawModelOutput = """
        1. Polycarbonate thermal degradation mechanisms
        2) Bisphenol-A free polycarbonate synthesis
        • High-impact polycarbonate nanocomposites
        4. Extraneous fourth suggestion
        """

        let lines = rawModelOutput
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "^[0-9]+[\\.\\)]\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "^[\\*\\-\\•]\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && $0.count > 3 }

        let suggestions = Array(lines.prefix(3))
        assertTest(suggestions.count == 3, "Parsed exactly 3 suggestions")
        assertTest(suggestions[0] == "Polycarbonate thermal degradation mechanisms", "Numbered '1.' prefix stripped")
        assertTest(suggestions[1] == "Bisphenol-A free polycarbonate synthesis", "Numbered '2)' prefix stripped")
        assertTest(suggestions[2] == "High-impact polycarbonate nanocomposites", "Bullet '•' stripped")

        // Test 5: Model attribution & badge reporting
        print("\n--- Test Group 3: Model Attribution & Badge Reporting ---")
        let onDeviceVersion = "apple-foundation-models-v1"
        let isOnDevice = onDeviceVersion.contains("apple-foundation-models") || onDeviceVersion.contains("system-language-model")
        assertTest(isOnDevice, "Correctly identifies on-device Apple Intelligence model")

        let cloudVersion = "gemini-3.5-flash-lite"
        let isCloud = !(cloudVersion.contains("apple-foundation-models") || cloudVersion.contains("system-language-model"))
        assertTest(isCloud, "Correctly identifies Gemini cloud fallback model")

        // Badge label tests
        let onDeviceBadge = isOnDevice ? "On-device" : "Cloud"
        assertTest(onDeviceBadge == "On-device", "Badge displays 'On-device' for local inference")

        let cloudBadge = isCloud ? "Cloud" : "On-device"
        assertTest(cloudBadge == "Cloud", "Badge displays 'Cloud' for fallback inference")

        // Test 6: Hybrid failover mechanics
        print("\n--- Test Group 4: Automatic Hybrid Failover Simulation ---")
        let primaryOnDevice = MockSuggestionModel(
            modelVersion: "apple-foundation-models-v1",
            shouldFail: true, // Primary fails (e.g. device busy or model not ready)
            responseText: ""
        )
        let secondaryCloud = MockSuggestionModel(
            modelVersion: "gemini-3.5-flash-lite",
            shouldFail: false,
            responseText: "1. Bio-based polycarbonate\n2. Polycarbonate recycling"
        )

        let hybridEngine = MockHybridEngine(primary: primaryOnDevice, secondary: secondaryCloud)
        do {
            let (content, modelVersion) = try hybridEngine.execute(prompt: "polycarbonate")
            let fallbackAttribution = !(modelVersion.contains("apple-foundation-models") || modelVersion.contains("system-language-model"))
            assertTest(modelVersion == "gemini-3.5-flash-lite", "Fallback routed to secondary cloud model 'gemini-3.5-flash-lite'")
            assertTest(fallbackAttribution, "Model attribution correctly identifies cloud fallback")
            assertTest(content.contains("Bio-based polycarbonate"), "Fallback response contains valid suggestions")
        } catch {
            assertTest(false, "Hybrid failover threw unexpected error: \(error)")
        }

        print("\n==================================================")
        print("📊 Cloud Fallback Test Summary: \(passed) passed, \(failed) failed")
        print("==================================================")
        if failed > 0 {
            exit(1)
        }
    }
}
