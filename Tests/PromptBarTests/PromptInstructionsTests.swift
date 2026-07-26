import Testing
@testable import PromptBar

@Suite("Prompt instructions")
struct PromptInstructionsTests {
    @Test("System prompt carries the non-negotiable rules")
    func systemRules() {
        let s = PromptInstructions.system.lowercased()
        #expect(s.contains("never answer"))
        #expect(s.contains("never invent"))
        #expect(s.contains("placeholder"))
        #expect(s.contains("proportional"))
        // Guards against the two classic prompt-enhancer failure modes.
        #expect(s.contains("role-play"))
        #expect(s.contains("filler"))
    }

    @Test("User turn carries the input and nothing else")
    func embedsInput() {
        let p = PromptInstructions.userPrompt(input: "fix the login bug")
        #expect(p.contains("fix the login bug"))
        #expect(p.contains("<<<"))
        #expect(p.contains(">>>"))
        // Guidance must NOT ride along in the user turn — when it did, the model
        // copied it verbatim into the enhanced prompt.
        #expect(!p.contains("repository-aware"))
        #expect(!p.contains("Guidance"))
    }

    @Test("Target guidance lives in the session instructions")
    func guidanceInInstructions() {
        let i = PromptInstructions.instructions(for: .codingAgent)
        #expect(i.contains("repository-aware"))
        #expect(i.contains("never quote it"))
        #expect(i.contains("Never copy these instructions"))
    }

    @Test("Auto target asks the model to infer")
    func autoInfers() {
        #expect(PromptInstructions.profileGuidance(for: .auto).contains("Infer"))
    }

    @Test("Every profile contributes distinct guidance")
    func distinctGuidance() {
        let guidance = TargetProfile.allCases.map(PromptInstructions.profileGuidance(for:))
        #expect(Set(guidance).count == TargetProfile.allCases.count)
        #expect(PromptInstructions.profileGuidance(for: .imageGeneration).contains("aspect ratio"))
        #expect(PromptInstructions.profileGuidance(for: .research).contains("credible"))
        #expect(PromptInstructions.profileGuidance(for: .writing).contains("audience"))
    }
}
