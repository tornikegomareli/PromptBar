import SwiftUI
import AppKit

/// Error / compatibility state: a centred alert-style layout, with the symbol,
/// explanation and recovery action all supplied by the model layer rather than
/// switched on here — so a new provider needs no changes in this view.
struct FailureView: View {
    @Bindable var model: PromptBarViewModel
    let failure: EnhancementFailure

    private var recovery: RecoveryAction { model.recovery(for: failure) }

    var body: some View {
        VStack(spacing: 12) {
            icon
                .padding(.bottom, 2)

            Text(failure.title)
                .font(Theme.font(15, .semibold))
                .multilineTextAlignment(.center)

            Text(failure.explanation(provider: model.capabilities.providerName))
                .font(Theme.font(12.5))
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Button("Copy Original") { model.copyOriginal() }
                    .buttonStyle(.glass)
                if let title = recovery.title {
                    Button(title) { perform(recovery) }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var icon: some View {
        if failure.isSpinner {
            InlineSpinner(size: 26)
        } else {
            Image(systemName: failure.symbolName)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.warn)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func perform(_ action: RecoveryAction) {
        switch action {
        case .none:
            break
        case .retry:
            model.regenerate()
        case .editInput:
            model.editInput()
        case .openURL(let url, _):
            NSWorkspace.shared.open(url)
            model.requestClose()
        }
    }
}
