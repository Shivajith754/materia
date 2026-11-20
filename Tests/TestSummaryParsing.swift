import Foundation

// MARK: - Standalone Test for Summary Generation & Parsing Logic

struct AISummaryResult: Hashable, Sendable {
    let overview: String
    let keyFindings: String
    let researchGaps: String
    let evidenceText: String
    let interpretationText: String
    let abstractsUsedCount: Int
    var responseTime: TimeInterval? = nil

    init(
        overview: String = "",
        keyFindings: String = "",
        researchGaps: String = "",
        evidenceText: String,
        interpretationText: String,
        abstractsUsedCount: Int,
        responseTime: TimeInterval? = nil
    ) {
        self.overview = overview
        self.keyFindings = keyFindings
        self.researchGaps = researchGaps
        self.evidenceText = evidenceText
        self.interpretationText = interpretationText
        self.abstractsUsedCount = abstractsUsedCount
        self.responseTime = responseTime
    }
}

func parseSummary(text: String, paperCount: Int) -> AISummaryResult {
    let lines = text.components(separatedBy: .newlines)
    var currentSection: SummarySection? = nil
    var overviewLines: [String] = []
    var findingsLines: [String] = []
    var gapsLines: [String] = []

    enum SummarySection {
        case overview
        case keyFindings
        case researchGaps
    }

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        let isHeaderLike = trimmed.hasPrefix("#") || trimmed.hasPrefix("**") || trimmed.hasPrefix("1.") || trimmed.hasPrefix("2.") || trimmed.hasPrefix("3.") || trimmed.hasSuffix(":")

        if lower.contains("overview") && isHeaderLike {
            currentSection = .overview
            continue
        } else if (lower.contains("key finding") || lower.contains("findings")) && isHeaderLike {
            currentSection = .keyFindings
            continue
        } else if (lower.contains("research gap") || lower.contains("gaps") || lower.contains("limitations") || lower.contains("missing evidence")) && isHeaderLike {
            currentSection = .researchGaps
            continue
        }

        switch currentSection {
        case .overview:
            overviewLines.append(line)
        case .keyFindings:
            findingsLines.append(line)
        case .researchGaps:
            gapsLines.append(line)
        case nil:
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                overviewLines.append(line)
            }
        }
    }

    let overview = overviewLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    let keyFindings = findingsLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    let researchGaps = gapsLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

    if !overview.isEmpty || !keyFindings.isEmpty || !researchGaps.isEmpty {
        let evidenceText: String
        if !overview.isEmpty && !keyFindings.isEmpty {
            evidenceText = """
            **Overview**
            \(overview)

            **Key Findings**
            \(keyFindings)
            """
        } else if !overview.isEmpty {
            evidenceText = overview
        } else {
            evidenceText = keyFindings
        }

        let interpretationText: String = !researchGaps.isEmpty
            ? "**Research Gaps**\n\(researchGaps)"
            : ""

        return AISummaryResult(
            overview: overview,
            keyFindings: keyFindings,
            researchGaps: researchGaps,
            evidenceText: evidenceText,
            interpretationText: interpretationText,
            abstractsUsedCount: paperCount
        )
    }

    return AISummaryResult(
        evidenceText: text.trimmingCharacters(in: .whitespacesAndNewlines),
        interpretationText: "",
        abstractsUsedCount: paperCount
    )
}

@main
struct SummaryParsingTests {
    static func main() {
        print("🧪 Testing AI Summary Parsing with Improved 3-Section Format...")

        let sampleModelOutput = """
        ### OVERVIEW
        Bio-based polycarbonates derived from isosorbide and 1,4-cyclohexanedicarboxylic acid exhibit comparable tensile stiffness to commercial bisphenol-A polycarbonate (BPA-PC), while offering superior optical transparency and a lower carbon footprint. However, their thermal degradation threshold is moderately lower.

        ### KEY FINDINGS
        • Isosorbide-based copolycarbonates achieved a tensile modulus of 2.35 GPa and tensile strength of 72 MPa, closely matching petroleum-based PC (2.4 GPa) [Kim et al., 2023].
        • Incorporation of 15 mol% bio-derived diol enhanced glass transition temperature (Tg) up to 162°C while maintaining >89% visible light transmittance [Journal of Polymer Science, 2024].
        • Char yield at 600°C reached 18.4% under nitrogen atmosphere, demonstrating promising intrinsic flame retardancy without halogenated additives [Novel Polycarbonate Synthesis, 2022].
        • Melt-compounding with cellulose nanocrystals (2 wt%) increased storage modulus by 28% at 100°C without inducing premature thermal degradation [Zhang & Lee, 2021].

        ### RESEARCH GAPS
        • Long-term hydrolytic degradation under warm, humid conditions (85°C / 85% RH) remains unmeasured across all retrieved studies.
        • Impact toughness at sub-zero temperatures (-20°C to -40°C) is not reported for any of the isosorbide copolycarbonate grades.
        • Continuous melt-processing scalability has not been evaluated beyond 50-gram batch reactor scales.
        """

        let result = parseSummary(text: sampleModelOutput, paperCount: 4)

        assert(!result.overview.isEmpty, "Overview should not be empty")
        assert(result.overview.contains("Bio-based polycarbonates"), "Overview text matches expected content")

        assert(!result.keyFindings.isEmpty, "Key findings should not be empty")
        assert(result.keyFindings.contains("Kim et al., 2023"), "Key findings preserve exact citations")
        assert(result.keyFindings.contains("2.35 GPa"), "Key findings preserve quantitative metrics")

        assert(!result.researchGaps.isEmpty, "Research gaps should not be empty")
        assert(result.researchGaps.contains("Long-term hydrolytic degradation"), "Research gaps identify critical limitations")

        assert(result.evidenceText.contains("**Overview**"), "evidenceText formats Overview for existing UI")
        assert(result.evidenceText.contains("**Key Findings**"), "evidenceText formats Key Findings for existing UI")
        assert(result.interpretationText.contains("**Research Gaps**"), "interpretationText formats Research Gaps for existing UI")
        assert(result.abstractsUsedCount == 4, "Paper count preserved")

        print("✅ All 8 summary parsing assertions PASSED successfully!")
    }
}
