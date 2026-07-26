import Foundation

/// The canonical section layout for the Structured variant.
///
/// Both the format and the heading vocabulary live here so producers and the
/// result view agree. Previously the Apple adapter emitted these strings and
/// `ResultView` re-declared its own lowercase copy of the list — which had
/// already drifted (it styled an "Acceptance criteria" heading nothing emits).
struct StructuredSections: Sendable, Equatable {
    var objective: String
    var context: String
    var requirements: [String]
    var constraints: [String]
    var expectedOutput: String

    /// Every heading this layout can emit, in order.
    static let headings = ["Objective", "Context", "Requirements", "Constraints", "Expected output"]

    /// Case-insensitive lookup used by the result view to style heading lines.
    static let headingKeys = Set(headings.map { $0.lowercased() })

    /// Renders `Heading\nbody` blocks separated by blank lines.
    var text: String {
        func bullets(_ items: [String]) -> String {
            items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.drop { $0 == "-" || $0 == "•" || $0 == " " } }
                .map(String.init)
                .filter { !$0.isEmpty }
                .map { "- \($0)" }
                .joined(separator: "\n")
        }

        var blocks: [String] = []
        func add(_ heading: String, _ body: String) {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            blocks.append("\(heading)\n\(trimmed)")
        }

        add("Objective", objective)
        add("Context", context)
        add("Requirements", bullets(requirements))
        add("Constraints", bullets(constraints))
        add("Expected output", expectedOutput)
        return blocks.joined(separator: "\n\n")
    }
}

/// Provider-neutral post-processing shared by every adapter.
///
/// This was private to the Apple adapter, which meant a second provider had to
/// re-derive fence stripping, missing-context normalisation, ordering and
/// empty-variant filtering — and none of it could be tested without a live
/// model. It depends on nothing provider-specific.
enum EnhancementAssembler {

    /// Assembles the three variants into a bundle in display order, dropping
    /// any the provider left empty.
    static func bundle(
        intent: String,
        minimal: String,
        balanced: String,
        structured: String,
        missing: [String],
        detectedProfile: TargetProfile?
    ) -> EnhancementBundle {
        let ordered: [(SuggestionStyle, String)] = [
            (.balanced, balanced),
            (.structured, structured),
            (.minimal, minimal),
        ]

        let suggestions = ordered.compactMap { style, raw -> PromptSuggestion? in
            let prompt = clean(raw)
            guard !prompt.isEmpty else { return nil }
            return PromptSuggestion(style: style, title: style.title, prompt: prompt)
        }

        return EnhancementBundle(
            detectedIntent: clean(intent).lowercased(),
            detectedProfile: detectedProfile,
            missingContext: normalizeMissing(missing),
            suggestions: suggestions
        )
    }

    /// Strips markdown fences and surrounding whitespace that models add
    /// despite being told not to.
    static func clean(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = String(s.drop { $0 != "\n" }).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    /// Missing-context items are rendered as chips, so they must be short bare
    /// phrases: models often return sentence-cased items ending in a period.
    /// Capped at three (PRD §12) and de-duplicated.
    static func normalizeMissing(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let phrase = item
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".;,"))
                .lowercased()
            guard !phrase.isEmpty, seen.insert(phrase).inserted else { continue }
            result.append(phrase)
            if result.count == 3 { break }
        }
        return result
    }
}
