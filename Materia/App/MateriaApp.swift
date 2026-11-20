import SwiftUI

@main
struct MateriaApp: App {
    @State private var store: ResearchStore

    init() {
        // Ensure Firebase and App Check are configured BEFORE any services or views are initialized
        FirebaseConfigurator.configure()
        _store = State(wrappedValue: ResearchStore())
    }

    var body: some Scene {
        WindowGroup {
            RootNavigationView()
                .environment(store)
        }
    }
}

private struct RootNavigationView: View {
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ResearchView(navigationPath: $navigationPath)
                .navigationDestination(for: ResearchRequest.self) { request in
                    ResultsView(request: request)
                }
        }
    }
}
