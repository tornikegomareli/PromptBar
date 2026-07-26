import Testing
import SwiftUI
import AppKit
@testable import PromptBar

/// Guards the result body against growing tall enough to push the panel's
/// footer actions off screen.
///
/// This bounds the body only. It does not reproduce the original clipping bug,
/// whose cause was the panel window never resizing at all (see
/// `OverlayWindowController.makePanel`) — that needs a real window on screen,
/// and `NSHostingView.fittingSize` reports zero for the full panel headlessly.
///
/// What it does cover is the bound that replaced a character-count threshold.
/// Character count is a poor proxy for rendered height: the Structured variant
/// is short in characters but tall in lines (headings, bullets, blank lines),
/// so it sat at ~526 characters — half the old 1100 threshold — while laying
/// out ~413pt tall.
@MainActor
@Suite("Prompt body layout")
struct PromptBodyLayoutTests {

    /// The Structured output for "Check the codebase and make sure to
    /// understand the build system" — the case that clipped the panel.
    private static let structured = StructuredSections(
        objective: "Provide a detailed review of the codebase.",
        context: "Review the codebase for correctness, readability, and edge cases, and list the most important issues you find.",
        requirements: [
            "Understand the build system.",
            "Identify and document issues.",
            "Provide actionable recommendations.",
        ],
        constraints: [
            "Preserve the user's original wording.",
            "Avoid unnecessary details.",
            "Focus on the codebase's functionality.",
        ],
        expectedOutput: "A detailed review of the codebase, including a list of issues and recommendations for improvement."
    ).text

    /// Lays the body out at panel width and returns the height it demands.
    private func measuredHeight(of text: String) -> CGFloat {
        let host = NSHostingView(
            rootView: PromptBody(text: text, key: .structured)
                .frame(width: PanelMetrics.contentWidth)
        )
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    /// The ceiling the body may never exceed, mirroring the view's own cap.
    private var cap: CGFloat {
        min(520, max(200, (NSScreen.main?.visibleFrame.height ?? 900) - 260))
    }

    @Test("The structured variant that clipped the footer is bounded")
    func structuredVariantIsBounded() {
        let text = Self.structured
        // Establish that this text is exactly the shape the old heuristic
        // missed: well under the retired 1100-character threshold.
        #expect(text.count < 1100)
        #expect(text.components(separatedBy: "\n").count > 12)
        #expect(measuredHeight(of: text) <= cap)
    }

    @Test("A pathologically long prompt is still bounded")
    func longPromptIsBounded() {
        let text = (1...400).map { "- requirement number \($0)" }.joined(separator: "\n")
        #expect(measuredHeight(of: text) <= cap)
    }

    @Test("A short prompt hugs its content instead of padding to the cap")
    func shortPromptHugsContent() {
        let height = measuredHeight(of: "Rewrite this paragraph.")
        #expect(height > 0)
        #expect(height < cap)
    }
}
