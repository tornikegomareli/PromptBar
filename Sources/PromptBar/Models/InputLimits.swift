import Foundation

/// Input size thresholds for one provider (PRD §20).
///
/// A property of the model rather than a global constant: Apple's on-device
/// session shares a single 4,096-token window between the instructions, the
/// schema, the input and all three generated prompts, whereas a large-context
/// provider could accept far more. The provider declares its own numbers via
/// `ModelCapabilities`.
struct InputLimits: Sendable, Equatable {
    /// Warn above this many characters.
    var soft: Int
    /// Refuse above this many characters — never silently truncate.
    var hard: Int

    enum State: Equatable, Sendable {
        case empty
        case ok
        case warning
        case tooLong
    }

    func state(for text: String) -> State {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if count == 0 { return .empty }
        if count < soft { return .ok }
        if count < hard { return .warning }
        return .tooLong
    }

    /// Tuned for a 4,096-token shared window at roughly four characters per
    /// token, leaving room for the instructions, schema and three outputs.
    static let conservative = InputLimits(soft: 2_000, hard: 4_000)
}
