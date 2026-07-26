import Foundation
import FoundationModels

/// The structured sections of the "Structured" variant.
///
/// These are separate fields rather than one blob of text on purpose: asking
/// the model to "put each heading on its own line" does not work — it happily
/// returns `Objective: … Context: …` inline. Generating the parts and
/// assembling the layout in Swift makes the format deterministic.
@Generable
struct StructuredPrompt {
    @Guide(description: "One imperative sentence stating the goal. No heading, no label.")
    var objective: String

    @Guide(description: """
    One or two sentences of background, using only what the user supplied. \
    Use a [bracketed placeholder] for anything they did not say. Do not restate the \
    objective or echo the user's sentence — this is the situation around the task. \
    No heading, no label.
    """)
    var context: String

    @Guide(description: """
    Three to five short requirement phrases. Each is a bare phrase with no \
    leading dash, number, or label.
    """)
    var requirements: [String]

    // Kept short and free of examples. A longer guide spelling out what not to
    // invent was copied into the output verbatim — the model emitted "No invented
    // circumstances such as what the user has already read" as a constraint —
    // and the same phrasing pushed it into restating the requirements.
    @Guide(description: """
    Zero to two short phrases limiting how the work is done, taken only from what \
    the user already said. Each is a bare phrase with no leading dash, number, or \
    label. Do not restate a requirement. Usually the user gave no limits: return an \
    empty list.
    """)
    var constraints: [String]

    @Guide(description: "One sentence naming exactly what the assistant should produce. No heading, no label.")
    var expectedOutput: String
}

/// The full guided-generation payload (PRD §19).
///
/// Field order matters — the model generates in declaration order, so the cheap
/// classification fields come first and inform the rewrites, and the variants
/// run shortest to longest.
@Generable
struct GeneratedEnhancement {
    @Guide(description: """
    A two-to-four word lowercase label for the kind of task, for example \
    "code refactor", "product design", "blog post", "market research".
    """)
    var intent: String

    @Guide(description: """
    MINIMAL variant. Keep the user's own wording and vocabulary, but name the \
    dimensions the task should cover and what the answer should contain. \
    One or two sentences. It must add real information — never return the user's \
    sentence back unchanged. For the input "review this code" a good minimal \
    rewrite is: "Review the following code for correctness, readability, and edge \
    cases, and list the most important issues you find." No headings, no bullets, \
    no invented specifics.
    """)
    var minimal: String

    // The loosest of the three fields, and so the one that drifts. Structured
    // cannot answer the user because its subfields force imperative framing;
    // Minimal has a worked example. Balanced had neither, and for a
    // question-shaped input "say what the response should contain" was read as
    // an instruction to write the response — it answered "recommend me summer
    // books" with a list of novels.
    @Guide(description: """
    BALANCED variant. An instruction addressed to the assistant, in the \
    imperative, as two or three short paragraphs of plain prose. Clarify the \
    goal, add only context and constraints the user actually implied, and \
    describe what the response should contain — describe that answer, never \
    write it. For the input "can you recommend summer books" a good balanced \
    rewrite starts "Recommend summer reading ...", never "Here are some books \
    ..." and never "I would like ...". It must add real information: never hand \
    the user's own sentence back unchanged. No headings and no bullet lists.
    """)
    var balanced: String

    var structured: StructuredPrompt

    // Generated last, so it is judged against the rewrites above rather than
    // guessed before the model has considered the task at all.
    // No example phrases here on purpose: when this guide listed samples, the
    // model returned those exact samples for unrelated requests.
    @Guide(description: """
    At most three short lowercase noun phrases naming details that this particular \
    request leaves open and that would genuinely change the answer. Derive them \
    from this request only. Leave the list empty when nothing important is \
    missing — empty is a good answer. Never name something the user already said, \
    and never repeat a word from their request.
    """)
    var missing: [String]
}

extension StructuredPrompt {
    /// Bridges the wire type into the canonical, provider-neutral layout.
    var sections: StructuredSections {
        StructuredSections(
            objective: objective,
            context: context,
            requirements: requirements,
            constraints: constraints,
            expectedOutput: expectedOutput
        )
    }
}
