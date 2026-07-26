import Foundation

/// The three enhancement styles PromptBar returns (PRD §8).
///
/// These are intentionally *meaningfully different* takes on the same
/// intention, not paraphrases of one another.
enum SuggestionStyle: String, CaseIterable, Sendable, Identifiable, Codable {
    case balanced
    case structured
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .structured: "Structured"
        case .minimal: "Minimal"
        }
    }

    /// One-tap keyboard index (⌘1/⌘2/⌘3).
    var shortcutIndex: Int {
        switch self {
        case .balanced: 1
        case .structured: 2
        case .minimal: 3
        }
    }
}

/// Target-model profile (PRD §9). Auto-detection stays *visible and editable*.
enum TargetProfile: String, CaseIterable, Sendable, Identifiable, Codable {
    case auto
    case generalAI
    case codingAgent
    case research
    case writing
    case imageGeneration

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .generalAI: "General AI"
        case .codingAgent: "Coding Agent"
        case .research: "Research"
        case .writing: "Writing"
        case .imageGeneration: "Image Generation"
        }
    }
}

/// A single enhanced-prompt variant.
struct PromptSuggestion: Identifiable, Sendable, Hashable, Codable {
    var id: SuggestionStyle { style }
    var style: SuggestionStyle
    var title: String
    var prompt: String
}

/// The full result of one enhancement pass.
struct EnhancementBundle: Sendable, Hashable, Codable {
    /// Short lowercase label like "product design".
    var detectedIntent: String
    /// The profile the provider inferred, and only when the user left Target on
    /// Auto. `nil` means "nothing was inferred" — never echo the user's own
    /// choice back here.
    var detectedProfile: TargetProfile?
    /// Materially-absent details the target AI would need (PRD §12).
    var missingContext: [String]
    /// One entry per style, in display order, each style at most once.
    var suggestions: [PromptSuggestion]

    func suggestion(for style: SuggestionStyle) -> PromptSuggestion? {
        suggestions.first { $0.style == style }
    }
}

/// The request handed to a `PromptModel` (PRD §18).
struct EnhancementRequest: Sendable, Hashable {
    var rawInput: String
    var profile: TargetProfile
}
