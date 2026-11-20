import SwiftUI

// MARK: - Brand

private enum Brand {
    static let background = Color.black
    static let surface    = Color(white: 0.09)
    static let line       = Color.white.opacity(0.12)
    static let text       = Color.white
    static let muted      = Color.white.opacity(0.55)
    static let faint      = Color.white.opacity(0.35)

    /// Wordmark uses the system serif for a refined, editorial feel.
    static let wordmark   = Font.system(size: 44, weight: .semibold, design: .serif)
}

// MARK: - View

struct ResearchView: View {
    @Environment(ResearchStore.self) private var store
    @Binding var navigationPath: NavigationPath

    @AppStorage("allowCloudSuggestions") private var allowCloudSuggestions: Bool = false
    @FocusState private var isSearchFocused: Bool

    @State private var localAIStatus: LocalAIStatus? = nil
    @State private var suggestionsResult: AISuggestionResult? = nil
    @State private var isLoadingSuggestions: Bool = false
    @State private var suggestionTask: Task<Void, Never>? = nil

    private var isLocalAIAvailable: Bool {
        if case .available = localAIStatus { return true }
        return false
    }

    private var trimmedQuery: String {
        store.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showCloudConsentNotice: Bool {
        !isLocalAIAvailable && !allowCloudSuggestions && trimmedQuery.count >= 3
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                searchCard
                exampleQuestionsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Brand.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(.white)
        .task {
            localAIStatus = await store.checkLocalAIStatus()
        }
        .onChange(of: store.queryText) { _, newValue in
            debounceSuggestions(for: newValue)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Matéria")
                .font(Brand.wordmark)
                .foregroundStyle(Brand.text)

            Text("Polymer science & materials engineering")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Search

    private var searchCard: some View {
        @Bindable var bindableStore = store

        return VStack(alignment: .leading, spacing: 0) {
            // Input
            HStack(alignment: .top, spacing: 10) {
                TextField(
                    "",
                    text: $bindableStore.queryText,
                    prompt: Text("What are you researching?").foregroundStyle(Brand.faint),
                    axis: .vertical
                )
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Brand.text)
                .lineLimit(1...5)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { submitSearch() }

                if !store.queryText.isEmpty {
                    Button {
                        store.queryText = ""
                        suggestionsResult = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Brand.faint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear question")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            // Suggestions / status
            suggestionsArea

            Divider().overlay(Brand.line)

            // Action row
            HStack {
                if allowCloudSuggestions && !isLocalAIAvailable {
                    Button {
                        allowCloudSuggestions = false
                        suggestionsResult = nil
                    } label: {
                        Label("Cloud suggestions on", systemImage: "xmark")
                            .labelStyle(TrailingIconLabelStyle())
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: submitSearch) {
                    HStack(spacing: 6) {
                        Text("Research")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.footnote.weight(.bold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
                    .opacity(trimmedQuery.isEmpty ? 0.3 : 1)
                }
                .buttonStyle(.plain)
                .disabled(trimmedQuery.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSearchFocused ? Color.white.opacity(0.35) : Brand.line, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: isSearchFocused)
    }

    @ViewBuilder
    private var suggestionsArea: some View {
        if isLoadingSuggestions {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Finding better searches…")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

        } else if let result = suggestionsResult, !result.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Suggested searches")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)

                    Spacer()

                    // Generic badge only — no model names.
                    Label(result.isOnDevice ? "On-device" : "Cloud",
                          systemImage: result.isOnDevice ? "iphone" : "cloud")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Brand.muted)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

                ForEach(Array(result.suggestions.enumerated()), id: \.element) { index, suggestion in
                    Button {
                        applySuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundStyle(Brand.text)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)

                            Spacer(minLength: 8)

                            Image(systemName: "arrow.up.left")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.faint)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < result.suggestions.count - 1 {
                        Divider().overlay(Brand.line).padding(.leading, 18)
                    }
                }
            }
            .padding(.bottom, 8)
            .transition(.opacity)

        } else if showCloudConsentNotice {
            VStack(alignment: .leading, spacing: 10) {
                Text("Smart suggestions aren't available on this device. You can turn on cloud suggestions — your question will be sent online to generate them.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    allowCloudSuggestions = true
                    debounceSuggestions(for: store.queryText, immediate: true)
                } label: {
                    Text("Turn on cloud suggestions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }

    // MARK: Examples

    private var exampleQuestionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Try asking")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.muted)
                .padding(.bottom, 6)

            let questions = store.exampleQuestions

            ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                Button {
                    runExample(question)
                } label: {
                    HStack(spacing: 12) {
                        Text(question.text)
                            .font(.body)
                            .foregroundStyle(Brand.text)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.faint)
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < questions.count - 1 {
                    Divider().overlay(Brand.line)
                }
            }
        }
    }

    // MARK: Actions

    private func submitSearch() {
        guard !trimmedQuery.isEmpty else { return }
        isSearchFocused = false
        navigationPath.append(ResearchRequest(query: trimmedQuery))
    }

    private func runExample(_ question: ExampleQuestion) {
        isSearchFocused = false
        store.queryText = question.text
        navigationPath.append(ResearchRequest(query: question.text))
    }

    private func applySuggestion(_ suggestion: String) {
        store.queryText = suggestion
        isSearchFocused = true
    }

    private func debounceSuggestions(for query: String, immediate: Bool = false) {
        suggestionTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            suggestionsResult = nil
            isLoadingSuggestions = false
            return
        }

        // If local AI is unavailable and user has not consented to cloud, do not call backend
        guard isLocalAIAvailable || allowCloudSuggestions else {
            suggestionsResult = nil
            isLoadingSuggestions = false
            return
        }

        suggestionTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            if Task.isCancelled { return }

            isLoadingSuggestions = true
            defer { isLoadingSuggestions = false }

            do {
                let result = try await store.fetchSuggestions(for: trimmed, allowCloudFallback: allowCloudSuggestions)
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    suggestionsResult = result
                }
            } catch {
                if Task.isCancelled { return }
                print("[ResearchView] Suggestion fetch error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Helpers

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.font(.caption2)
        }
    }
}
