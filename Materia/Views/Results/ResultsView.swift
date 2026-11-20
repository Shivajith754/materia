import SwiftUI

// MARK: - Brand (same tokens as ResearchView)

private enum Brand {
    static let background = Color.black
    static let surface    = Color(white: 0.09)
    static let line       = Color.white.opacity(0.12)
    static let text       = Color.white
    static let muted      = Color.white.opacity(0.55)
    static let faint      = Color.white.opacity(0.35)
}

// MARK: - View

struct ResultsView: View {
    @Environment(ResearchStore.self) private var store

    let request: ResearchRequest

    @State private var papers: [ScientificPaper] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    // AI Summary State
    @State private var aiSummaryState: AISummaryUIState = .idle

    private var papersWithAbstractsCount: Int {
        papers.filter {
            guard let abs = $0.abstract else { return false }
            return !abs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                queryHeader

                if isLoading {
                    loadingView
                } else if let errorMessage {
                    errorView(message: errorMessage)
                } else if papers.isEmpty {
                    emptyView
                } else {
                    aiSummaryCard
                    papersList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Brand.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(.white)
        .task(id: request) {
            await fetchPapers()
        }
    }

    // MARK: - Query header

    private var queryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.displayTitle)
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)

            if !isLoading && errorMessage == nil && !papers.isEmpty {
                Text("\(papers.count) papers from OpenAlex")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Brand.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - AI summary card

    private var aiSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch aiSummaryState {
            case .idle:
                idleSummaryView
            case .loading:
                loadingSummaryView
            case .failure(let message):
                failureSummaryView(message: message)
            case .success(let result):
                successSummaryView(result: result)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Brand.line, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.25), value: aiSummaryState.id)
    }

    private var idleSummaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI summary", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Brand.text)

            Text(papersWithAbstractsCount > 0
                 ? "Get the key findings from \(papersWithAbstractsCount) paper abstracts in one read."
                 : "None of these papers have abstracts, so there's nothing to summarize.")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)

            if papersWithAbstractsCount > 0 {
                Button {
                    Task { await generateAISummary() }
                } label: {
                    Label("Summarize", systemImage: "sparkles")
                }
                .buttonStyle(PillButtonStyle(filled: true))
                .padding(.top, 2)
            }
        }
    }

    private var loadingSummaryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().tint(.white)

                Text("Summarizing…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
            }

            Text("Reading the abstracts. This usually takes a few seconds.")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
    }

    private func failureSummaryView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't create the summary", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.text)

            Text(message)
                .font(.caption)
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try again") {
                Task { await generateAISummary() }
            }
            .buttonStyle(PillButtonStyle(filled: false))
        }
    }

    private func successSummaryView(result: AISummaryResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("AI summary", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Brand.text)

                Spacer()

                Text("\(result.abstractsUsedCount) abstracts")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)

                Button {
                    Task { await generateAISummary() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Regenerate summary")
            }

            Divider().overlay(Brand.line)

            // What the papers say
            VStack(alignment: .leading, spacing: 10) {
                Text("What the papers say")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.muted)

                FormattedSummaryText(raw: result.evidenceText,
                                     font: .system(size: 16),
                                     color: Brand.text)
            }

            // AI interpretation (visually separated from the evidence)
            if !result.interpretationText.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Interpretation", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.muted)

                    FormattedSummaryText(raw: result.interpretationText,
                                         font: .system(size: 15),
                                         color: Brand.text.opacity(0.8))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Based only on the abstracts of the papers below. Check the papers before relying on any detail.")
                .font(.caption2)
                .foregroundStyle(Brand.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Papers list

    private var papersList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Papers")
                .font(.headline)
                .foregroundStyle(Brand.text)

            LazyVStack(spacing: 12) {
                ForEach(papers) { paper in
                    PaperRowView(paper: paper)
                }
            }
        }
    }

    // MARK: - Loading & error states

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .padding(.top, 36)

            Text("Searching the literature…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Brand.faint)

            Text("Search failed")
                .font(.headline)
                .foregroundStyle(Brand.text)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)

            Button("Try again") {
                Task { await fetchPapers() }
            }
            .buttonStyle(PillButtonStyle(filled: true))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Brand.faint)

            Text("No papers found")
                .font(.headline)
                .foregroundStyle(Brand.text)

            Text("Nothing matched \"\(request.displayTitle)\". Try broader polymer or application keywords.")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Actions

    private func fetchPapers() async {
        isLoading = true
        errorMessage = nil
        aiSummaryState = .idle

        do {
            papers = try await store.searchPapers(query: request.query)
            isLoading = false
        } catch is CancellationError {
            // Task was cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Cancelled
        } catch let openAlexError as OpenAlexError {
            errorMessage = openAlexError.localizedDescription
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func generateAISummary() async {
        guard !papers.isEmpty else { return }
        aiSummaryState = .loading

        do {
            let result = try await store.summarizePapers(question: request.query, papers: papers)
            aiSummaryState = .success(result)
        } catch is CancellationError {
            // Ignore cancellation
        } catch {
            aiSummaryState = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Supporting types

private enum AISummaryUIState {
    case idle
    case loading
    case success(AISummaryResult)
    case failure(String)

    /// Stable identity so the card can animate between states.
    var id: Int {
        switch self {
        case .idle: 0
        case .loading: 1
        case .success: 2
        case .failure: 3
        }
    }
}

/// White filled pill (primary) or outlined pill (secondary).
private struct PillButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Color.black : Brand.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(filled ? Color.white : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(filled ? Color.clear : Color.white.opacity(0.4), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Summary text renderer

/// Renders AI text as clean blocks. Handles the markdown the model tends to
/// return (headings, bullets, numbered lists, **bold**, line breaks), which a
/// plain `Text(LocalizedStringKey:)` collapses into one messy paragraph.
private struct FormattedSummaryText: View {
    let raw: String
    var font: Font = .body
    var color: Color = Brand.text

    private enum Block {
        case heading(String)
        case paragraph(String)
        case bullet(String)
        case numbered(String, String)
    }

    private static let bulletPrefixes = ["- ", "* ", "• ", "– ", "— "]

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []

        func flush() {
            guard !paragraph.isEmpty else { return }
            result.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flush()
            } else if line.hasPrefix("#") {
                flush()
                let title = line.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { result.append(.heading(title)) }
            } else if let prefix = Self.bulletPrefixes.first(where: { line.hasPrefix($0) }) {
                flush()
                result.append(.bullet(String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)))
            } else if let match = line.wholeMatch(of: /(\d+)[.)]\s+(.+)/) {
                flush()
                result.append(.numbered(String(match.1), String(match.2)))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    inline(text)
                        .font(font.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.top, 4)

                case .paragraph(let text):
                    inline(text)
                        .font(font)
                        .foregroundStyle(color)

                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•")
                            .font(font)
                            .foregroundStyle(Brand.faint)
                        inline(text)
                            .font(font)
                            .foregroundStyle(color)
                    }

                case .numbered(let number, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(number).")
                            .font(font)
                            .monospacedDigit()
                            .foregroundStyle(Brand.faint)
                        inline(text)
                            .font(font)
                            .foregroundStyle(color)
                    }
                }
            }
        }
        .lineSpacing(5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    /// Inline markdown only (bold, italic, code, links). Falls back to plain text.
    private func inline(_ string: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: string, options: options) {
            return Text(attributed)
        }
        return Text(string)
    }
}
