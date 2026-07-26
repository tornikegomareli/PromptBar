import Foundation

/// Lightweight, deterministic prompt diagnostics (PRD §11).
///
/// This runs instantly and locally, giving the user immediate feedback while
/// the model produces richer missing-context suggestions. It deliberately
/// avoids a false-precision numeric score in favour of descriptive states.
enum PromptQuality: String, Sendable {
    case incomplete = "Incomplete"
    case usable = "Usable"
    case clear = "Clear"
    case wellSpecified = "Well specified"
}

struct PromptDiagnostic: Identifiable, Sendable, Hashable {
    enum Status: Sendable { case pass, warn }
    var id: String { label }
    var status: Status
    var label: String
}

struct PromptLintResult: Sendable {
    var quality: PromptQuality
    var diagnostics: [PromptDiagnostic]
}

enum PromptLinter {
    // A few tiny heuristics. Not authoritative — just fast signal.
    private static let actionVerbs = [
        "write", "build", "create", "refactor", "review", "fix", "design",
        "research", "analyze", "analyse", "summarize", "summarise", "explain",
        "generate", "implement", "compare", "draft", "translate", "improve",
        "debug", "test", "optimize", "optimise", "plan", "make", "add", "remove",
    ]
    private static let formatCues = [
        "format", "bullet", "list", "table", "json", "markdown", "section",
        "steps", "outline", "paragraph", "word", "length",
    ]
    private static let constraintCues = [
        "must", "avoid", "don't", "do not", "without", "only", "constraint",
        "preserve", "keep", "limit", "no ", "never", "should not",
    ]
    private static let criteriaCues = [
        "success", "criteria", "acceptance", "done when", "good result",
        "quality", "correct", "requirement",
    ]

    static func lint(_ text: String) -> PromptLintResult {
        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter }.map(String.init)
        let wordSet = Set(words)

        let hasAction = actionVerbs.contains { wordSet.contains($0) }
        // "Target artifact identified": a noun-ish token after the verb, or any
        // reference to a concrete thing. Cheap proxy: reasonable length + a noun.
        let hasArtifact = words.count >= 3
        let hasFormat = formatCues.contains { lower.contains($0) }
        let hasConstraints = constraintCues.contains { lower.contains($0) }
        let hasCriteria = criteriaCues.contains { lower.contains($0) }

        let diagnostics: [PromptDiagnostic] = [
            .init(status: hasAction ? .pass : .warn, label: "Clear action"),
            .init(status: hasArtifact ? .pass : .warn, label: "Target artifact identified"),
            .init(status: hasFormat ? .pass : .warn, label: "Output format"),
            .init(status: hasConstraints ? .pass : .warn, label: "Constraints"),
            .init(status: hasCriteria ? .pass : .warn, label: "Success criteria"),
        ]

        let passes = diagnostics.filter { $0.status == .pass }.count
        let quality: PromptQuality = switch passes {
        case 0, 1: .incomplete
        case 2: .usable
        case 3, 4: .clear
        default: .wellSpecified
        }

        return PromptLintResult(quality: quality, diagnostics: diagnostics)
    }
}
