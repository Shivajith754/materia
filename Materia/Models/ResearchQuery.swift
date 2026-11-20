import Foundation

struct ExampleQuestion: Identifiable, Hashable, Sendable {
    let id: String
    let text: String

    static let defaults: [ExampleQuestion] = [
        ExampleQuestion(
            id: "q-implants",
            text: "Which biocompatible polymers work best for spinal implants?"
        ),
        ExampleQuestion(
            id: "q-5g",
            text: "What polymers provide low dielectric loss for 5G mmWave substrates?"
        ),
        ExampleQuestion(
            id: "q-battery",
            text: "Which polymers resist electrolytes in lithium-ion battery separators?"
        )
    ]
}

struct ResearchRequest: Hashable, Sendable {
    let query: String

    var displayTitle: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Scientific Search" : trimmed
    }
}
