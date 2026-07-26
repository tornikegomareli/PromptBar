import SwiftUI

/// Manual-entry state. Right-aligned field labels + native controls, with the
/// Cancel / Generate pair bottom-right in standard macOS dialog order.
struct InputView: View {
    @Bindable var model: PromptBarViewModel
    var inputFocused: FocusState<Bool>.Binding

    private let labelColumn: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What do you want the AI to do?")
                .font(Theme.font(15, .semibold))

            PromptTextEditor(
                text: $model.rawInput,
                placeholder: "Describe the task in your own words — rough is fine.",
                height: 104,
                focused: inputFocused
            )

            VStack(alignment: .leading, spacing: 10) {
                row("Target:") {
                    Picker("", selection: $model.profile) {
                        ForEach(TargetProfile.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 230)
                }
                row("Style:") {
                    Picker("", selection: $model.selectedStyle) {
                        ForEach(SuggestionStyle.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            }

            if model.inputLimitState != .ok && model.inputLimitState != .empty {
                InputLimitLabel(state: model.inputLimitState)
            }

            HStack(spacing: 9) {
                Spacer()
                Button("Cancel") { model.requestClose() }
                    .buttonStyle(.glass)
                Button("Generate") { model.generateFromInput() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(16)
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.font(13))
                .foregroundStyle(Theme.label2)
                .frame(width: labelColumn, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }
}

struct InputLimitLabel: View {
    let state: InputLimits.State

    var body: some View {
        switch state {
        case .empty, .ok:
            EmptyView()
        case .warning:
            label("Long input — enhancement may be less reliable.", Theme.warn)
        case .tooLong:
            label("Too long for reliable on-device enhancement.", Theme.danger)
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
            Text(text).font(Theme.font(11.5))
        }
        .foregroundStyle(color)
    }
}
