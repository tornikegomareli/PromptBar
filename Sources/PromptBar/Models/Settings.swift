import Foundation

/// Settings sections (design handoff §6).
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case shortcuts = "Shortcuts"
    case history = "History"
    case privacy = "Privacy"
    case about = "About"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Local-history retention (PRD §15: 7 / 30 / 90 days / Never).
enum RetentionPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case never = "Never"

    var id: String { rawValue }
    var label: String { rawValue }

    /// Days after which entries are pruned; `nil` means keep forever.
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .never: nil
        }
    }
}

/// An app whose prompts are never written to local history.
struct ExcludedApp: Codable, Identifiable, Hashable, Sendable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// One recorded enhancement (PRD §15). Stored only when history is enabled.
struct HistoryEntry: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var original: String
    var enhanced: String
    var profile: TargetProfile
    var style: SuggestionStyle
    var date: Date
    var wasEdited: Bool
    var wasCopied: Bool
}

/// The full keyboard map shown in Settings › Shortcuts (design handoff fixture).
struct ShortcutRow: Identifiable, Sendable {
    var action: String
    var keys: String
    var id: String { action }

    static let all: [ShortcutRow] = [
        .init(action: "Open PromptBar", keys: "⇧⌥Space"),
        .init(action: "Instant Enhance", keys: "⌃⌥P"),
        .init(action: "Copy & close", keys: "↵"),
        .init(action: "Generate from input", keys: "⌘↵"),
        .init(action: "Select Balanced", keys: "⌘1"),
        .init(action: "Select Structured", keys: "⌘2"),
        .init(action: "Select Minimal", keys: "⌘3"),
        .init(action: "Regenerate", keys: "⌘R"),
        .init(action: "Copy w/o closing", keys: "⇧⌘C"),
        .init(action: "Edit result", keys: "⇥"),
        .init(action: "Settings", keys: "⌘,"),
        .init(action: "Close", keys: "esc"),
    ]
}

/// Privacy bullets, derived from what the active provider actually does — a
/// networked provider must not be described as making zero network requests.
enum PrivacyCopy {
    /// - Parameter watchingSelection: whether the selection popup is running.
    ///   It must change what this says. With the popup on, PromptBar reads text
    ///   the user selects in other apps, and a privacy page that still claimed
    ///   PromptBar only looks when asked would be false.
    static func points(
        for capabilities: ModelCapabilities,
        watchingSelection: Bool = false
    ) -> [String] {
        var points = ["No account and no sign-in \u{2014} ever."]
        if capabilities.runsOnDevice {
            points.append("Zero network requests for enhancement. \(capabilities.providerName) already lives on your Mac.")
        } else {
            points.append("Prompts are sent to \(capabilities.providerName) to be enhanced, and nowhere else.")
        }
        points.append("Each enhancement runs in a fresh session, so prompts never leak between requests.")
        points.append("No general clipboard monitoring. PromptBar reads the pasteboard only when you ask.")
        if watchingSelection {
            points.append("Selection popup is on \u{2014} PromptBar reads what you select in other apps to decide whether to offer the chip. The text is read as you select it, never written down, and never sent anywhere.")
            points.append("Password fields are never read, and neither are your excluded apps.")
        }
        return points
    }
}
