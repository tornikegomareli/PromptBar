import SwiftUI

/// Generating state: the original as a quote, the active tags, the local lint
/// readout, and a quiet spinner. No layout churn while the model works.
struct GeneratingView: View {
    @Bindable var model: PromptBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionLabel(text: "Original")
            QuotedOriginal(text: model.rawInput, size: 13, lineLimit: 3)

            HStack(spacing: 7) {
                Tag(text: model.profile.displayName)
                Tag(text: model.selectedStyle.title)
            }

            HairlineDivider()

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    SectionLabel(text: "Prompt check")
                    Text(lintStatus)
                        .font(Theme.font(11, .semibold))
                        .foregroundStyle(Theme.warn)
                }
                if let lint = model.lint {
                    ForEach(lint.diagnostics) { diag in
                        HStack(spacing: 7) {
                            Image(systemName: diag.status == .pass ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(diag.status == .pass ? Theme.ok : Theme.label3)
                            Text(diag.label)
                                .font(Theme.font(12.5))
                                .foregroundStyle(diag.status == .pass ? Theme.label : Theme.label2)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                InlineSpinner()
                Text(model.capabilities.runsOnDevice ? "Generating on this Mac…" : "Generating…")
                    .font(Theme.font(12.5))
                    .foregroundStyle(Theme.label2)
                Spacer()
                Button("Cancel") { model.cancelGeneration() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var lintStatus: String {
        switch model.lint?.quality {
        case .some(.wellSpecified): "Well specified"
        case .some(.clear): "Clear"
        case .some(.usable): "Usable"
        default: "Incomplete"
        }
    }
}
