import Foundation

/// The model seam (PRD §18).
///
/// Everything a caller must know to swap providers lives here: what the
/// provider can accept, how it describes itself, whether it is available, how
/// to recover from its failures, and how to enhance a prompt.
///
/// ## Contract for adapters
/// - `enhance` may assume nothing about availability; it must check for itself
///   and throw the matching `EnhancementFailure`.
/// - `enhance` throws `EnhancementFailure` for every expected condition and
///   `CancellationError` when superseded. Any other error is treated as
///   `.generationFailed` by callers.
/// - The returned `suggestions` are in display order and each style appears at
///   most once. Use `EnhancementAssembler` to get this for free.
/// - A `.structured` suggestion must use the canonical section layout produced
///   by `StructuredSections.text` so the result view can style headings.
protocol PromptModel: Sendable {
    /// Declared synchronously so the UI can size inputs and word its privacy
    /// claims without awaiting the model.
    nonisolated var capabilities: ModelCapabilities { get }

    /// `nil` when the provider can serve a request right now.
    func availability() async -> EnhancementFailure?

    /// Warm the provider when there is a meaningful opportunity (PRD §19).
    func prewarm() async

    func enhance(_ request: EnhancementRequest) async throws -> EnhancementBundle

    /// What the user can do about a failure. Provider-specific by nature.
    nonisolated func recovery(for failure: EnhancementFailure) -> RecoveryAction
}

extension PromptModel {
    func prewarm() async {}

    /// Provider-neutral recovery. Adapters override only the cases they can do
    /// better on (Apple, for instance, can deep-link to its Settings pane).
    nonisolated func recovery(for failure: EnhancementFailure) -> RecoveryAction {
        switch failure {
        case .inputTooLong:
            .editInput(title: "Edit Input")
        case .unsupportedDevice:
            .none
        case .unsupportedLanguage:
            // No force-English request flag exists yet, so promising one would
            // just loop on the same failure.
            .none
        case .modelDownloading:
            .retry(title: "Check Again")
        default:
            .retry(title: "Try Again")
        }
    }
}
