import Foundation
import FoundationModels

// MARK: - Client

/// The real on-device model (PRD §18/§19): an actor wrapping
/// `SystemLanguageModel` with a fresh `LanguageModelSession` per request.
///
/// A fresh session per enhancement is deliberate — prompt rewriting gains
/// nothing from a conversation transcript, and reuse would let one request's
/// content leak into the next.
actor AppleSystemPromptModel: PromptModel {
    private let model = SystemLanguageModel.default

    nonisolated let capabilities = ModelCapabilities(
        providerName: "Apple Intelligence",
        runsOnDevice: true,
        inputLimits: .conservative
    )

    /// Apple can do better than a bare retry for the one failure the user can
    /// actually fix from System Settings.
    nonisolated func recovery(for failure: EnhancementFailure) -> RecoveryAction {
        switch failure {
        case .appleIntelligenceDisabled:
            // The "Apple Intelligence & Siri" pane on macOS 26.
            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                return .openURL(url, title: "Open System Settings")
            }
            return .none
        case .unsupportedDevice:
            return .none
        case .inputTooLong:
            return .editInput(title: "Edit Input")
        case .modelDownloading:
            return .retry(title: "Check Again")
        case .unsupportedLanguage:
            return .none
        default:
            return .retry(title: "Try Again")
        }
    }

    /// Low randomness: consistency matters far more than creative prose here.
    private static let options = GenerationOptions(
        temperature: 0.3,
        maximumResponseTokens: 1400
    )

    // MARK: Availability

    func availability() async -> EnhancementFailure? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .unsupportedDevice
            case .appleIntelligenceNotEnabled: return .appleIntelligenceDisabled
            case .modelNotReady: return .modelDownloading
            @unknown default: return .modelUnavailable
            }
        @unknown default:
            return .modelUnavailable
        }
    }

    func prewarm() async {
        guard case .available = model.availability else { return }
        makeSession().prewarm()
    }

    // MARK: Generation

    func enhance(_ request: EnhancementRequest) async throws -> EnhancementBundle {
        if let failure = await availability() { throw failure }

        let session = makeSession(profile: request.profile)
        let prompt = PromptInstructions.userPrompt(input: request.rawInput)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedEnhancement.self,
                options: Self.options
            )
            try Task.checkCancellation()
            return Self.bundle(from: response.content, request: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch {
            throw EnhancementFailure.generationFailed
        }
    }

    private func makeSession(profile: TargetProfile = .auto) -> LanguageModelSession {
        LanguageModelSession(
            model: model,
            instructions: PromptInstructions.instructions(for: profile)
        )
    }

    // MARK: Mapping

    /// Maps framework errors onto the product's failure states (PRD §21).
    private static func map(_ error: LanguageModelSession.GenerationError) -> EnhancementFailure {
        switch error {
        case .exceededContextWindowSize: .inputTooLong
        case .guardrailViolation, .refusal: .guardrailBlocked
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .assetsUnavailable: .modelDownloading
        case .decodingFailure, .rateLimited, .concurrentRequests, .unsupportedGuide: .generationFailed
        @unknown default: .generationFailed
        }
    }

    private static func bundle(
        from generated: GeneratedEnhancement,
        request: EnhancementRequest
    ) -> EnhancementBundle {
        EnhancementAssembler.bundle(
            intent: generated.intent,
            minimal: generated.minimal,
            balanced: generated.balanced,
            structured: generated.structured.sections.text,
            missing: generated.missing,
            // The provider is not asked to classify the target, so nothing is
            // inferred; never echo the user's own selection back.
            detectedProfile: nil
        )
    }
}
