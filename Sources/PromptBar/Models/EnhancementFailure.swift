import Foundation

/// Product-level failure states (PRD §21).
///
/// Split into conditions any provider can hit and conditions specific to a
/// local, on-device provider, so a networked provider has somewhere to land
/// instead of collapsing everything into `.generationFailed`.
enum EnhancementFailure: Error, Sendable, Equatable {
    // Any provider
    case modelUnavailable
    case inputTooLong
    case unsupportedLanguage
    case guardrailBlocked
    case generationCancelled
    case generationFailed

    // Local, on-device providers
    case appleIntelligenceDisabled
    case modelDownloading
    case unsupportedDevice

    // Networked providers
    case networkUnavailable
    case notAuthorized
    case quotaExceeded
    case timedOut

    var title: String {
        switch self {
        case .appleIntelligenceDisabled: "Apple Intelligence is off"
        case .modelDownloading: "Model still downloading"
        case .unsupportedDevice: "Needs a Mac with Apple silicon"
        case .unsupportedLanguage: "This language isn't supported yet"
        case .inputTooLong: "This prompt is too long"
        case .modelUnavailable: "Model unavailable"
        case .guardrailBlocked: "Couldn't process that one"
        case .generationCancelled: "Cancelled"
        case .generationFailed: "Enhancement hiccuped"
        case .networkUnavailable: "No connection"
        case .notAuthorized: "Not signed in"
        case .quotaExceeded: "Quota reached"
        case .timedOut: "Took too long"
        }
    }

    /// Explanation, with the provider named rather than hard-coded to Apple.
    func explanation(provider: String) -> String {
        switch self {
        case .appleIntelligenceDisabled:
            "Turn on Apple Intelligence in System Settings to use on-device enhancement. Everything PromptBar does stays on your Mac."
        case .modelDownloading:
            "PromptBar becomes available automatically when the download finishes. Keep working — we'll be ready shortly."
        case .unsupportedDevice:
            "On-device enhancement uses the Apple Intelligence language model, which needs Apple silicon. PromptBar can't run its local model on this Mac."
        case .unsupportedLanguage:
            "\(provider) doesn't support this language yet. PromptBar can still enhance English prompts."
        case .inputTooLong:
            "Too long for reliable enhancement. Select the essential section or shorten the supporting context — PromptBar won't silently truncate your text."
        case .modelUnavailable:
            "PromptBar couldn't reach \(provider). Give it another go in a moment."
        case .guardrailBlocked:
            "\(provider) declined this request. Try rephrasing it."
        case .generationCancelled:
            "The enhancement was cancelled."
        case .generationFailed:
            "Something went sideways while enhancing. Give it another go."
        case .networkUnavailable:
            "\(provider) needs a network connection and none is available."
        case .notAuthorized:
            "PromptBar isn't authorised to use \(provider). Check your credentials in Settings."
        case .quotaExceeded:
            "You've reached your usage limit for \(provider)."
        case .timedOut:
            "\(provider) didn't answer in time. Give it another go."
        }
    }

    /// SF Symbol shown on the failure screen.
    var symbolName: String {
        switch self {
        case .appleIntelligenceDisabled: "apple.intelligence"
        case .unsupportedDevice: "desktopcomputer.trianglebadge.exclamationmark"
        case .unsupportedLanguage: "globe"
        case .inputTooLong: "text.badge.xmark"
        case .networkUnavailable: "wifi.slash"
        case .notAuthorized: "person.badge.key"
        case .quotaExceeded: "gauge.with.dots.needle.100percent"
        case .timedOut: "clock.badge.exclamationmark"
        default: "exclamationmark.triangle"
        }
    }

    /// Whether the failure screen shows a progress spinner instead of a symbol.
    var isSpinner: Bool { self == .modelDownloading }
}
