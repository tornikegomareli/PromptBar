import Foundation

/// A deterministic, offline `PromptModel`.
///
/// This is the second adapter that keeps the seam honest: it exercises every
/// part of the contract — capabilities, availability, recovery, ordering and
/// the canonical structured layout — without a language model, which is what
/// makes the view model testable.
actor StaticPromptModel: PromptModel {
    nonisolated let capabilities: ModelCapabilities

    private var latency: Duration
    private var forcedFailure: EnhancementFailure?

    init(
        latency: Duration = .zero,
        forcedFailure: EnhancementFailure? = nil,
        capabilities: ModelCapabilities = ModelCapabilities(
            providerName: "the offline model",
            runsOnDevice: true,
            inputLimits: .conservative
        )
    ) {
        self.latency = latency
        self.forcedFailure = forcedFailure
        self.capabilities = capabilities
    }

    func setLatency(_ latency: Duration) { self.latency = latency }
    func setForcedFailure(_ failure: EnhancementFailure?) { forcedFailure = failure }

    func availability() async -> EnhancementFailure? { forcedFailure }

    func enhance(_ request: EnhancementRequest) async throws -> EnhancementBundle {
        if let forcedFailure { throw forcedFailure }
        if latency > .zero { try await Task.sleep(for: latency) }
        try Task.checkCancellation()

        let raw = request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferred = request.profile == .auto ? Self.detectProfile(raw) : nil
        let subject = raw.isEmpty ? "the requested task" : raw
        let sentence = subject.prefix(1).uppercased() + subject.dropFirst()

        let sections = StructuredSections(
            objective: sentence + ".",
            context: "[Add any background the assistant needs.]",
            requirements: [
                "Prioritise correctness and clarity.",
                "Preserve the original intention; do not add unrequested scope.",
            ],
            constraints: ["State assumptions instead of inventing facts."],
            expectedOutput: "A directly usable result, plus a brief note on key decisions."
        )

        return EnhancementAssembler.bundle(
            intent: Self.detectIntent(raw),
            minimal: "\(sentence) Be specific and state any assumptions.",
            balanced: """
            \(sentence).

            Focus on an actionable, correct result. Where important details are \
            missing, note your assumptions rather than inventing facts.
            """,
            structured: sections.text,
            missing: Self.missingContext(for: inferred ?? request.profile),
            detectedProfile: inferred
        )
    }

    // MARK: - Heuristics

    static func detectProfile(_ text: String) -> TargetProfile {
        let l = text.lowercased()
        if ["refactor", "code", "bug", "function", "class", "api", "test", "repo", "swift"]
            .contains(where: l.contains) { return .codingAgent }
        if ["research", "compare", "competitor", "sources", "evidence", "market"]
            .contains(where: l.contains) { return .research }
        if ["image", "photo", "render", "illustration", "logo", "poster"]
            .contains(where: l.contains) { return .imageGeneration }
        if ["write", "post", "email", "blog", "tweet", "linkedin", "copy", "article"]
            .contains(where: l.contains) { return .writing }
        return .generalAI
    }

    static func detectIntent(_ text: String) -> String {
        switch detectProfile(text) {
        case .codingAgent: "coding"
        case .research: "research"
        case .imageGeneration: "image gen"
        case .writing: "writing"
        case .generalAI, .auto: "general task"
        }
    }

    static func missingContext(for profile: TargetProfile) -> [String] {
        switch profile {
        case .codingAgent: ["target files", "testing expectations"]
        case .research: ["comparison dimensions", "source recency"]
        case .imageGeneration: ["aspect ratio", "visual style"]
        case .writing: ["target audience", "desired length"]
        case .generalAI, .auto: ["expected output format"]
        }
    }
}
