import Foundation

struct ScientificPaper: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let authors: [String]
    let journal: String?
    let publicationYear: Int?
    let citationCount: Int
    let abstract: String?
    let paperURL: URL?
    let doi: String?

    var formattedAuthors: String {
        switch authors.count {
        case 0:
            return "Authors not listed"
        case 1:
            return authors[0]
        case 2:
            return "\(authors[0]) & \(authors[1])"
        case 3:
            return "\(authors[0]), \(authors[1]) & \(authors[2])"
        default:
            return "\(authors[0]), \(authors[1]) et al."
        }
    }

    var formattedCitationCount: String {
        "\(citationCount) citation\(citationCount == 1 ? "" : "s")"
    }
}

extension ScientificPaper {
    init(work: OpenAlexWork) {
        self.id = work.id

        let rawTitle = work.title ?? work.displayName ?? "Untitled Work"
        let cleanTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = cleanTitle.isEmpty ? "Untitled Work" : cleanTitle

        let extractedAuthors: [String] = work.authorships?
            .compactMap { $0.author?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        self.authors = extractedAuthors

        self.journal = work.primaryLocation?.source?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicationYear = work.publicationYear
        self.citationCount = max(0, work.citedByCount ?? 0)
        self.abstract = Self.reconstructAbstract(from: work.abstractInvertedIndex)
        self.doi = work.doi
        self.paperURL = Self.resolveURL(
            doi: work.doi,
            primaryLocation: work.primaryLocation,
            openAccess: work.openAccess,
            workID: work.id
        )
    }

    static func reconstructAbstract(from invertedIndex: [String: [Int]]?) -> String? {
        guard let invertedIndex, !invertedIndex.isEmpty else { return nil }
        var wordsWithPositions: [(Int, String)] = []
        for (word, positions) in invertedIndex {
            for position in positions {
                wordsWithPositions.append((position, word))
            }
        }
        guard !wordsWithPositions.isEmpty else { return nil }
        wordsWithPositions.sort { $0.0 < $1.0 }
        let reconstructed = wordsWithPositions.map { $0.1 }.joined(separator: " ")
        let trimmed = reconstructed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func resolveURL(
        doi: String?,
        primaryLocation: OpenAlexLocation?,
        openAccess: OpenAlexOpenAccess?,
        workID: String
    ) -> URL? {
        if let doi, let url = URL(string: doi), url.scheme != nil {
            return url
        }
        if let landing = primaryLocation?.landingPageUrl, let url = URL(string: landing), url.scheme != nil {
            return url
        }
        if let oa = openAccess?.oaUrl, let url = URL(string: oa), url.scheme != nil {
            return url
        }
        if let pdf = primaryLocation?.pdfUrl, let url = URL(string: pdf), url.scheme != nil {
            return url
        }
        if let url = URL(string: workID), url.scheme != nil {
            return url
        }
        return nil
    }
}
