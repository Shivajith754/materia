import Foundation
import os

private let logger = Logger(subsystem: "com.materia.research.Materia", category: "EnvironmentConfig")

/// Manages environment configuration and secrets for local development.
public enum EnvironmentConfig: Sendable {
    /// Known placeholder values that should not be sent as real authentication keys.
    private static let knownPlaceholders: Set<String> = [
        "your_openalex_api_key_here",
        "your_api_key_here",
        "your_key_here",
        "placeholder",
        "<your_key>",
        "<your_openalex_api_key_here>",
        "replace_me",
        "changeme"
    ]

    /// Returns true if a key matches typical placeholder text.
    public static func isPlaceholderKey(_ key: String?) -> Bool {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return false
        }
        let lower = key.lowercased()
        if knownPlaceholders.contains(lower) { return true }
        if lower.hasPrefix("your_") && lower.hasSuffix("_here") { return true }
        if lower.hasPrefix("<") && lower.hasSuffix(">") { return true }
        return false
    }

    /// Raw OpenAlex API key string as found in the environment, .env file, Info.plist, or UserDefaults.
    /// This includes placeholders if one has not yet been replaced.
    public static var rawOpenAlexApiKey: String? {
        // 1. Process Environment
        if let envValue = ProcessInfo.processInfo.environment["OPENALEX_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envValue.isEmpty {
            return envValue
        }

        #if DEBUG
        // 2. Parse local .env file
        if let fileValue = valueFromLocalEnv(key: "OPENALEX_API_KEY"), !fileValue.isEmpty {
            return fileValue
        }
        #endif

        // 3. Info.plist
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: "OPENALEX_API_KEY") as? String {
            let trimmed = infoValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.starts(with: "$") {
                return trimmed
            }
        }

        // 4. UserDefaults fallback
        if let userDefaultValue = UserDefaults.standard.string(forKey: "OPENALEX_API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userDefaultValue.isEmpty {
            return userDefaultValue
        }
        if let legacyKey = UserDefaults.standard.string(forKey: "openAlexApiKey")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyKey.isEmpty {
            return legacyKey
        }

        return nil
    }

    /// Retrieves the active OpenAlex API key for development if configured and not a placeholder.
    /// If an unedited placeholder is detected, returns nil to preserve anonymous access
    /// while logging a guidance notice.
    public static var openAlexApiKey: String? {
        guard let rawKey = rawOpenAlexApiKey else { return nil }
        if isPlaceholderKey(rawKey) {
            logger.info("OPENALEX_API_KEY is currently set to placeholder ('\(rawKey)'). Using anonymous OpenAlex access until a real key is provided in .env.")
            return nil
        }
        return rawKey
    }

    /// Returns true if an OpenAlex API key is configured and not a placeholder.
    public static var hasOpenAlexApiKey: Bool {
        openAlexApiKey != nil
    }

    /// Returns true if a placeholder key is configured.
    public static var hasPlaceholderApiKey: Bool {
        isPlaceholderKey(rawOpenAlexApiKey)
    }

    /// Sanitized preview of the key for diagnostics (e.g. "...abcd" or "placeholder")
    public static var sanitizedKeyPreview: String {
        if hasPlaceholderApiKey {
            return "placeholder (add your key to .env)"
        }
        guard let key = openAlexApiKey, !key.isEmpty else {
            return "none (anonymous)"
        }
        if key.count <= 4 {
            return "configured (length \(key.count))"
        }
        let suffix = key.suffix(4)
        return "configured (••••\(suffix))"
    }

    #if DEBUG
    /// Immutable environment cache loaded lazily and thread-safely on first access.
    /// Concurrency-safe in Swift 6 Complete Concurrency mode (Sendable immutable state).
    private static let localEnv: [String: String] = loadLocalEnv()

    /// Retrieves a value from the immutable local .env dictionary.
    private static func valueFromLocalEnv(key: String) -> String? {
        localEnv[key]
    }

    /// Parses the local .env file once into an immutable dictionary.
    private static func loadLocalEnv() -> [String: String] {
        var parsed: [String: String] = [:]
        var candidateURLs: [URL] = []

        // 1. Walk up from compile-time source path to find .env in repo root
        let sourceURL = URL(fileURLWithPath: #filePath)
        var currentDir = sourceURL.deletingLastPathComponent()
        for _ in 0..<5 {
            candidateURLs.append(currentDir.appendingPathComponent(".env"))
            let parent = currentDir.deletingLastPathComponent()
            if parent.path == currentDir.path { break }
            currentDir = parent
        }

        // 2. PROJECT_DIR / SRCROOT from Xcode build environment
        if let projectDir = ProcessInfo.processInfo.environment["PROJECT_DIR"], !projectDir.isEmpty {
            candidateURLs.append(URL(fileURLWithPath: projectDir).appendingPathComponent(".env"))
        }
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"], !srcRoot.isEmpty {
            candidateURLs.append(URL(fileURLWithPath: srcRoot).appendingPathComponent(".env"))
        }

        // 3. Current working directory fallback
        let cwd = FileManager.default.currentDirectoryPath
        if !cwd.isEmpty {
            candidateURLs.append(URL(fileURLWithPath: cwd).appendingPathComponent(".env"))
        }

        // 4. Bundle resource fallbacks if copied into app bundle
        if let bundleEnv = Bundle.main.url(forResource: ".env", withExtension: nil) {
            candidateURLs.append(bundleEnv)
        }
        if let bundleEnvWithoutDot = Bundle.main.url(forResource: "env", withExtension: nil) {
            candidateURLs.append(bundleEnvWithoutDot)
        }
        candidateURLs.append(Bundle.main.bundleURL.appendingPathComponent(".env"))

        for fileURL in candidateURLs {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // Ignore comments and empty lines
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                // Split at first '='
                if let equalIndex = trimmed.firstIndex(of: "=") {
                    var k = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    var v = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

                    // Strip leading 'export '
                    if k.hasPrefix("export ") {
                        k = String(k.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    // Strip surrounding quotes if present
                    if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
                        if v.count >= 2 {
                            v = String(v.dropFirst().dropLast())
                        }
                    } else {
                        // Strip trailing inline comment if unquoted
                        if let hashIndex = v.firstIndex(of: "#") {
                            v = String(v[..<hashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }

                    if !k.isEmpty {
                        parsed[k] = v
                    }
                }
            }
            logger.info("Loaded .env from \(fileURL.path) with \(parsed.count) entries")
            break
        }

        return parsed
    }
    #endif
}
