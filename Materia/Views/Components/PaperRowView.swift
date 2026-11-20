import SwiftUI

// MARK: - Brand (same tokens as ResearchView / ResultsView)

private enum Brand {
    static let surface = Color(white: 0.09)
    static let line    = Color.white.opacity(0.12)
    static let text    = Color.white
    static let muted   = Color.white.opacity(0.55)
    static let faint   = Color.white.opacity(0.35)
}

// MARK: - View

struct PaperRowView: View {
    let paper: ScientificPaper

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Journal & year
            if hasJournal || paper.publicationYear != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let journal = paper.journal, !journal.isEmpty {
                        Text(journal)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if let year = paper.publicationYear {
                        Text(String(year))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Brand.faint)
                    }
                }
            }

            // Title
            Text(paper.title)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(Brand.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Authors
            Text(paper.formattedAuthors)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .lineLimit(2)

            // Abstract
            if let abstract = paper.abstract, !abstract.isEmpty {
                Text(abstract)
                    .font(.subheadline)
                    .foregroundStyle(Brand.text.opacity(0.7))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Divider().overlay(Brand.line).padding(.top, 4)

            // Footer
            HStack(alignment: .center, spacing: 10) {
                if paper.citationCount > 0 {
                    Label("\(paper.citationCount) citations", systemImage: "quote.opening")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Brand.muted)
                }

                Spacer()

                if let url = paper.paperURL {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Text("Open paper")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Brand.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Brand.line, lineWidth: 1)
        )
    }

    private var hasJournal: Bool {
        guard let journal = paper.journal else { return false }
        return !journal.isEmpty
    }
}
