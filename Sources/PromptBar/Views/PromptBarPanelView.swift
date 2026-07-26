import SwiftUI
import AppKit

/// Root panel content — Apple Native chrome: a translucent Liquid Glass
/// surface, 12pt corners, hairline-separated regions.
///
/// The package deployment target is macOS 26, so `glassEffect` is always
/// available here; no `#available` fallback branch is reachable.
struct PromptBarPanelView: View {
    @Bindable var model: PromptBarViewModel
    @FocusState private var inputFocused: Bool
    @FocusState private var resultEditorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.isShowingSettings {
                SettingsView(model: model)
            } else {
                if showsTitlebar {
                    Titlebar(
                        runsOnDevice: model.capabilities.runsOnDevice,
                        onSettings: { model.openSettings() }
                    )
                    HairlineDivider()
                }

                switch model.phase {
                case .input:
                    InputView(model: model, inputFocused: $inputFocused)
                case .generating:
                    GeneratingView(model: model)
                case .result:
                    ResultView(model: model, editorFocused: $resultEditorFocused)
                case .failure(let failure):
                    FailureView(model: model, failure: failure)
                }
            }
        }
        .frame(width: panelWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.panel))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: Theme.hairline)
        )
        .foregroundStyle(Theme.label)
        .font(Theme.font(13))
        .background(keyboardCommands)
        // Keyed on the open token, not `.onAppear`: the panel is reused across
        // opens, so `.onAppear` fires only once per launch and every later open
        // would leave the field unfocused.
        .task(id: model.openToken) {
            if model.phase == .input, !model.isShowingSettings {
                inputFocused = true
            }
        }
        .onChange(of: model.isEditingResult) { _, editing in
            resultEditorFocused = editing
        }
    }

    private var panelWidth: CGFloat {
        if model.isShowingSettings { return PanelMetrics.settingsWidth }
        if case .failure = model.phase { return PanelMetrics.errorWidth }
        return PanelMetrics.width
    }

    private var showsTitlebar: Bool {
        switch model.phase {
        case .input, .generating, .result: true
        case .failure: false
        }
    }

    // MARK: - Keyboard

    @ViewBuilder
    private var keyboardCommands: some View {
        ZStack {
            // ⌘Return only means "generate" while composing; on a result it
            // would silently throw the visible result away.
            if model.phase == .input {
                Button("") { model.generateFromInput() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Button("") { handleRegenerate() }
                .keyboardShortcut("r", modifiers: .command)
            Button("") { model.copyWithoutClosing() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            ForEach(SuggestionStyle.allCases) { style in
                Button("") { model.select(style) }
                    .keyboardShortcut(KeyEquivalent(Character("\(style.shortcutIndex)")), modifiers: .command)
            }
            Button("") { handleEscape() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("") { model.openSettings() }
                .keyboardShortcut(",", modifiers: .command)

            if model.phase == .result && !model.isEditingResult {
                Button("") { model.copySelectedAndClose() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("") { model.beginEditing() }
                    .keyboardShortcut(.tab, modifiers: [])
                Button("") { moveSelection(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { moveSelection(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func handleEscape() {
        if model.isShowingSettings {
            model.closeSettings()
        } else if model.isEditingResult {
            model.endEditing()
        } else {
            model.requestClose()
        }
    }

    private func handleRegenerate() {
        guard model.phase == .result || model.phase == .generating else { return }
        model.regenerate()
    }

    private func moveSelection(_ delta: Int) {
        guard let bundle = model.bundle,
              let idx = bundle.suggestions.firstIndex(where: { $0.style == model.selectedStyle })
        else { return }
        let next = (idx + delta + bundle.suggestions.count) % bundle.suggestions.count
        model.select(bundle.suggestions[next].style)
    }
}

// MARK: - Titlebar

/// 38pt titlebar: brand mark + name, then the on-device lock label and a gear.
private struct Titlebar: View {
    var runsOnDevice: Bool
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            BrandMark(size: 15)
            Text("PromptBar").font(Theme.font(13, .semibold))
            Spacer()
            if runsOnDevice {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .medium))
                    Text("On-device").font(Theme.font(11))
                }
                .foregroundStyle(Theme.label2)
            }

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.label2)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }
}
