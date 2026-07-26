import Testing
import Foundation
@testable import PromptBar

/// A manual harness for judging instruction changes against the real on-device
/// model, rather than guessing at them.
///
/// The instruction set is the quality-critical part of PromptBar and nothing
/// deterministic can test it: the failure modes are all "the model wrote the
/// wrong *kind* of text". This prints every variant for a set of inputs chosen
/// because they have broken before, so a change can be read rather than assumed.
///
/// Off by default — it needs Apple Intelligence, takes seconds per input, and
/// its output is for a human to judge. Run it with:
///
///     PROMPTBAR_LIVE=1 swift test --filter LiveModelHarness
///
@Suite("Live model harness", .enabled(if: ProcessInfo.processInfo.environment["PROMPTBAR_LIVE"] != nil))
struct LiveModelHarness {

    /// Each of these has produced a real failure at some point.
    private static let inputs: [(label: String, input: String)] = [
        // Question-shaped input: the model answered these instead of rewriting,
        // returning an actual list of novels as the "Balanced" prompt.
        ("question", "Can u recommend for me summer books for read"),
        ("question", "can you tell me some interesting books to read for summer ?"),
        ("question", "what is the best way to structure a swift package"),
        // Terse imperative: the variants collapse into near-duplicates when
        // there is very little to work with.
        ("terse", "review this code"),
        // Concrete details that must survive the rewrite verbatim.
        ("detailed", "fix the retry logic in NetworkClient.swift, it drops the 429 case"),
    ]

    @Test("print every variant for the known-difficult inputs")
    func printVariants() async throws {
        let model = AppleSystemPromptModel()
        if let failure = await model.availability() {
            print("LIVE: model unavailable — \(failure). Nothing to judge.")
            return
        }
        for (label, input) in Self.inputs {
            print("\n======================= \(label) =======================")
            print("INPUT: \(input)")
            do {
                let bundle = try await model.enhance(
                    EnhancementRequest(rawInput: input, profile: .auto)
                )
                print("intent : \(bundle.detectedIntent)")
                print("missing: \(bundle.missingContext)")
                for suggestion in bundle.suggestions {
                    print("\n--- \(suggestion.title) ---")
                    print(suggestion.prompt)
                }
            } catch {
                print("LIVE: failed — \(error)")
            }
        }
        print("\n=======================================================")
    }
}
