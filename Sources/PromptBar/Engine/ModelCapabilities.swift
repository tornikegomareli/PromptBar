import Foundation

/// What a prompt-model provider can do and how it must be described.
///
/// Everything here used to be hard-coded to Apple's on-device model and spread
/// across the UI: the 4,096-token input ceiling lived in a global enum, the
/// "On-device" badge and the privacy copy were unconditional, and the failure
/// copy named Apple by hand. Moving them behind the seam means a second
/// provider declares its own truth and the UI simply reflects it.
struct ModelCapabilities: Sendable, Equatable {
    /// Human-readable provider name, used in failure copy and About.
    var providerName: String

    /// Whether inference happens on this Mac. Drives the "On-device" badge,
    /// the privacy claims, and the "Generating on this Mac…" wording — all of
    /// which become false the moment a network provider is added.
    var runsOnDevice: Bool

    /// How much input this provider can accept.
    var inputLimits: InputLimits

    static let unknown = ModelCapabilities(
        providerName: "the model",
        runsOnDevice: true,
        inputLimits: .conservative
    )
}

/// What the user can do about a failure. Supplied by the provider, because
/// recovery is provider-specific (Apple opens a Settings pane; a cloud
/// provider would open an account page or just retry).
enum RecoveryAction: Sendable, Equatable {
    case none
    case retry(title: String)
    case editInput(title: String)
    case openURL(URL, title: String)

    var title: String? {
        switch self {
        case .none: nil
        case .retry(let t), .editInput(let t): t
        case .openURL(_, let t): t
        }
    }
}
