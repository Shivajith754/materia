import Foundation
import FirebaseCore
import FirebaseAppCheck

enum FirebaseConfigurator: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var isConfigured = false

    /// Configures Firebase and App Check exactly once during app startup.
    /// Thread-safe and safe to call from any actor or thread.
    static func configure() {
        lock.lock()
        defer { lock.unlock() }

        guard !isConfigured else { return }

        // Check if Firebase was already configured
        if let apps = FirebaseApp.allApps, !apps.isEmpty {
            isConfigured = true
            return
        }

        // 1. Configure App Check factory strictly BEFORE FirebaseApp.configure()
        #if DEBUG
        // Development & Simulator builds: use App Check debug provider.
        // The debug token is generated dynamically by the Firebase SDK at runtime and
        // output to the Xcode console. It is not hardcoded or committed to version control.
        let providerFactory = AppCheckDebugProviderFactory()
        #else
        // Release builds: use Apple App Attest provider for hardware-backed device attestation.
        let providerFactory = AppAttestProviderFactory()
        #endif

        AppCheck.setAppCheckProviderFactory(providerFactory)

        // 2. Initialize Firebase
        FirebaseApp.configure()
        isConfigured = true
    }
}
