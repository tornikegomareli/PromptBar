import SwiftUI

/// Result state: quoted original, detected/missing metadata, a native
/// segmented variant picker, the prompt body, and a standard action footer.
struct ResultView: View {
    @Bindable var model: PromptBarViewModel
    var editorFocused: FocusState<Bool>.Binding

    var body: some View {
        if model.isEditingResult {
            EditView(model: model, editorFocused: editorFocused)
        } else {
            resultBody
        }
    }

    private var resultBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                QuotedOriginal(text: model.rawInput, size: 12.5, color: Theme.label2, lineLimit: 1)
                if let bundle = model.bundle {
                    FlowRow(spacing: 6) {
                        AccentTag(text: bundle.detectedIntent)
                        if !bundle.missingContext.isEmpty {
                            Text("Missing:")
                                .font(Theme.font(11.5))
                                .foregroundStyle(Theme.label3)
                            ForEach(bundle.missingContext, id: \.self) { Tag(text: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // NSSegmentedControl sizes its segments to fit, so a stretched
            // frame would just centre it. Left-aligned keeps it consistent with
            // the metadata above (design shows a full-width track).
            HStack(spacing: 0) {
                Picker("", selection: $model.selectedStyle) {
                    ForEach(model.bundle?.suggestions ?? []) { s in
                        Text(s.title).tag(s.style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PanelMetrics.contentInset)
            .padding(.top, 12)

            PromptBody(text: model.currentPromptText, key: model.selectedStyle)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            HairlineDivider()

            HStack(spacing: 9) {
                FooterHint(text: "⌘1–3 select · ⇥ edit · esc close")
                Spacer()
                Button("Regenerate") { model.regenerate() }
                    .buttonStyle(.glass)
                Button("Copy & Close") { model.copySelectedAndClose() }
                    .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
    }
}

// MARK: - Prompt body

/// Renders the prompt with bolded structured section headings.
///
/// The full text is laid out immediately — readable and selectable from the
/// first frame — and lines fade in as a non-blocking flourish, so streaming
/// flair never delays time-to-copy.
struct PromptBody: View {
    let text: String
    let key: SuggestionStyle

    /// Above this length the body scrolls at a fixed height so the panel can
    /// never grow past the screen; shorter prompts let the panel hug content.
    private static let scrollThreshold = 1100
    private static let scrollHeight: CGFloat = 320

    @State private var revealed = 0

    private var lines: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        Group {
            if text.count > Self.scrollThreshold {
                ScrollView { stack }.frame(height: Self.scrollHeight)
            } else {
                stack
            }
        }
        // `.task(id:)` so SwiftUI cancels the previous reveal when the variant
        // changes or the panel goes away — unstructured Tasks raced each other.
        .task(id: key) { await reveal() }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                lineView(line).opacity(i < revealed ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 5)
        } else if StructuredSections.headingKeys.contains(trimmed.lowercased()) {
            Text(trimmed)
                .font(Theme.font(13.5, .semibold))
                .foregroundStyle(Theme.label)
                .padding(.top, 5)
        } else {
            Text(line)
                .font(Theme.font(13.5))
                .foregroundStyle(Theme.label)
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reveal() async {
        revealed = 0
        let total = lines.count
        while revealed < total {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            withAnimation(.easeOut(duration: 0.15)) { revealed += 1 }
        }
    }
}
