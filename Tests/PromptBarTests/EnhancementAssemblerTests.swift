import Testing
@testable import PromptBar

@Suite("Structured sections")
struct StructuredSectionsTests {
    private var sample: StructuredSections {
        StructuredSections(
            objective: "Refactor the networking layer.",
            context: "Used across the app.",
            requirements: ["Keep behaviour", "Add tests"],
            constraints: ["No API changes"],
            expectedOutput: "A patch plus notes."
        )
    }

    @Test("Headings sit alone on their own line so the view can style them")
    func headingsOnOwnLines() {
        let lines = sample.text.components(separatedBy: "\n")
        #expect(lines.contains("Objective"))
        #expect(lines.contains("Requirements"))
        #expect(lines.contains("Expected output"))
        // The inline "Objective: …" shape is exactly what the model produced
        // before sections were generated separately.
        #expect(!sample.text.contains("Objective:"))
    }

    @Test("Every emitted heading is one the result view knows how to style")
    func headingVocabularyMatches() {
        let emitted = sample.text
            .components(separatedBy: "\n")
            .filter { StructuredSections.headingKeys.contains($0.lowercased()) }
        #expect(emitted.count == 5)
    }

    @Test("List items are bulleted, and pre-dashed items are not double-dashed")
    func bullets() {
        let s = StructuredSections(
            objective: "O", context: "C",
            requirements: ["- already dashed", "• bulleted", "plain"],
            constraints: [], expectedOutput: "E"
        )
        #expect(s.text.contains("- already dashed"))
        #expect(!s.text.contains("- - already dashed"))
        #expect(s.text.contains("- bulleted"))
        #expect(s.text.contains("- plain"))
    }

    @Test("Empty sections are omitted entirely")
    func omitsEmpty() {
        let s = StructuredSections(
            objective: "O", context: "  ",
            requirements: [], constraints: [], expectedOutput: "E"
        )
        #expect(!s.text.contains("Context"))
        #expect(!s.text.contains("Requirements"))
        #expect(s.text.contains("Objective"))
    }
}

@Suite("Enhancement assembler")
struct EnhancementAssemblerTests {
    private func bundle(
        minimal: String = "m", balanced: String = "b", structured: String = "s",
        missing: [String] = []
    ) -> EnhancementBundle {
        EnhancementAssembler.bundle(
            intent: "Code Refactor", minimal: minimal, balanced: balanced,
            structured: structured, missing: missing, detectedProfile: nil
        )
    }

    @Test("Suggestions come back in display order")
    func order() {
        #expect(bundle().suggestions.map(\.style) == [.balanced, .structured, .minimal])
    }

    @Test("Empty variants are dropped rather than shown blank")
    func dropsEmpty() {
        let b = bundle(minimal: "   ", structured: "")
        #expect(b.suggestions.map(\.style) == [.balanced])
    }

    @Test("Markdown fences are stripped")
    func stripsFences() {
        let b = EnhancementAssembler.bundle(
            intent: "x", minimal: "```\nhello\n```", balanced: "b",
            structured: "s", missing: [], detectedProfile: nil
        )
        #expect(b.suggestion(for: .minimal)?.prompt == "hello")
    }

    @Test("Intent is lowercased for the chip")
    func lowercasesIntent() {
        #expect(bundle().detectedIntent == "code refactor")
    }

    @Test("Missing context is normalised, de-duplicated and capped at three")
    func missingNormalisation() {
        let b = bundle(missing: [
            "Specific issues to identify.", "  ", "Supported platforms;",
            "specific issues to identify", "fourth item", "fifth item",
        ])
        #expect(b.missingContext == ["specific issues to identify", "supported platforms", "fourth item"])
    }
}

@Suite("Input limits")
struct InputLimitsTests {
    private let limits = InputLimits.conservative

    @Test func empty() { #expect(limits.state(for: "   ") == .empty) }
    @Test func ok() { #expect(limits.state(for: "hello") == .ok) }
    @Test func warning() {
        #expect(limits.state(for: String(repeating: "a", count: 3_000)) == .warning)
    }
    @Test func tooLong() {
        #expect(limits.state(for: String(repeating: "a", count: 5_000)) == .tooLong)
    }

    @Test("Limits are per-provider, not global")
    func perProvider() {
        let large = InputLimits(soft: 100_000, hard: 200_000)
        let text = String(repeating: "a", count: 5_000)
        #expect(limits.state(for: text) == .tooLong)
        #expect(large.state(for: text) == .ok)
    }
}
