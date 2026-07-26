import Testing
import AppKit
@testable import PromptBar

@Suite("Prompt linter")
struct PromptLinterTests {
    @Test("A bare instruction is at most 'usable'")
    func bareInstruction() {
        let result = PromptLinter.lint("review this code")
        #expect(result.diagnostics.first { $0.label == "Clear action" }?.status == .pass)
        #expect([.incomplete, .usable].contains(result.quality))
    }

    @Test("A fully specified prompt reads as 'well specified'")
    func specified() {
        let text = """
        Review this Swift function for correctness. Return findings as a \
        markdown list. You must not change the public API. A good result \
        lists concrete, actionable issues (success criteria).
        """
        let result = PromptLinter.lint(text)
        #expect(result.quality == .wellSpecified)
    }
}

@Suite("Clipboard service")
@MainActor
struct ClipboardServiceTests {
    @Test("Restore returns the prior value after a write")
    func restore() {
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        pb.setString("original", forType: .string)

        let service = ClipboardService(pasteboard: pb)
        #expect(service.readText() == "original")

        service.write("enhanced")
        #expect(pb.string(forType: .string) == "enhanced")

        #expect(service.restorePrevious())
        #expect(pb.string(forType: .string) == "original")
    }
}
