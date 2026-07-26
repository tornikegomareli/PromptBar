import SwiftUI
import AppKit

/// Settings in native macOS style: a toolbar of icon+label tabs across the
/// top, then grouped rows beneath — the standard System Settings shape.
struct SettingsView: View {
    @Bindable var model: PromptBarViewModel

    private var settings: AppSettings { model.settings }
    private let labelColumn: CGFloat = 128

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HairlineDivider()
            ScrollView {
                content
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A stable height across tabs avoids the window jumping on every
            // tab switch; the long tabs (Shortcuts) scroll within it.
            .frame(height: 302)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ZStack {
            GlassEffectContainer(spacing: 2) {
                HStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        tabButton(tab)
                    }
                }
            }
            HStack {
                Button { model.closeSettings() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.label2)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close settings (esc)")
                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 52)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let active = model.settingsTab == tab
        return Button {
            model.settingsTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol).font(.system(size: 15, weight: .regular))
                Text(tab.label).font(Theme.font(10.5))
            }
            .foregroundStyle(active ? Theme.accent : Theme.label2)
            .frame(width: 66, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if active {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.settingsTab {
        case .general: general
        case .shortcuts: shortcuts
        case .history: historyTab
        case .privacy: privacy
        case .about: about
        }
    }

    // MARK: General

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Open PromptBar") {
                HStack(spacing: 6) {
                    Keycap(label: "⇧", big: false)
                    Keycap(label: "⌥", big: false)
                    Keycap(label: "Space", big: false)
                }
            }
            row("Instant Enhance") {
                HStack(spacing: 6) {
                    Keycap(label: "⌃", big: false)
                    Keycap(label: "⌥", big: false)
                    Keycap(label: "P", big: false)
                }
            }
            row("Default target") {
                Picker("", selection: Binding(
                    get: { settings.defaultProfile },
                    set: { settings.defaultProfile = $0 }
                )) {
                    ForEach(TargetProfile.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 210)
            }
            row("Default style") {
                Picker("", selection: Binding(
                    get: { settings.defaultStyle },
                    set: { settings.defaultStyle = $0 }
                )) {
                    ForEach(SuggestionStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 260)
            }
            row("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(Theme.font(13))
            }
            row("Selection") {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Show a compile chip when I select text", isOn: Binding(
                        get: { settings.selectionPopupEnabled },
                        set: { model.setSelectionPopupEnabled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(Theme.font(13))

                    Text(selectionHint)
                        .font(Theme.font(11.5))
                        .foregroundStyle(needsAccessibility ? Theme.warn : Theme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 330, alignment: .leading)

                    if needsAccessibility {
                        Button("Open Accessibility Settings…") {
                            model.openAccessibilitySettings()
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var needsAccessibility: Bool {
        settings.selectionPopupEnabled && !model.isAccessibilityTrusted
    }

    private var selectionHint: String {
        if needsAccessibility {
            return "PromptBar needs Accessibility access to see what you select. "
                + "Enable PromptBar under Privacy & Security › Accessibility."
        }
        if settings.selectionPopupEnabled {
            return "PromptBar reads what you select in other apps to offer the chip. "
                + "Password fields and excluded apps are always skipped."
        }
        return "Off. The hotkey needs no permissions; this chip needs Accessibility access."
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        VStack(spacing: 0) {
            ForEach(Array(ShortcutRow.all.enumerated()), id: \.element.id) { i, row in
                HStack {
                    Text(row.action).font(Theme.font(13)).foregroundStyle(Theme.label)
                    Spacer()
                    Text(row.keys)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.label2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                if i < ShortcutRow.all.count - 1 {
                    HairlineDivider().padding(.leading, 12)
                }
            }
        }
        .groupedBox()
    }

    // MARK: History

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Enable local history", isOn: Binding(
                    get: { settings.historyEnabled },
                    set: { settings.historyEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .font(Theme.font(13, .medium))
                Text("Stored only in PromptBar's container. Never synced or uploaded.")
                    .font(Theme.font(11.5))
                    .foregroundStyle(Theme.label2)
            }

            VStack(alignment: .leading, spacing: 16) {
                row("Auto-delete after") {
                    Picker("", selection: Binding(
                        get: { settings.retention },
                        set: { settings.retention = $0; model.history.prune(using: $0) }
                    )) {
                        ForEach(RetentionPolicy.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 260)
                }
                row("Excluded apps") {
                    FlowRow(spacing: 6) {
                        ForEach(settings.excludedApps) { app in
                            HStack(spacing: 5) {
                                Text(app.name).font(Theme.font(11.5)).foregroundStyle(Theme.label2)
                                Button {
                                    settings.excludedApps.removeAll { $0.bundleID == app.bundleID }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.label3)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous).fill(Theme.controlFill))
                            .hairlineBorder(radius: Theme.Radius.tag)
                        }
                        AddExcludedAppMenu(settings: settings)
                    }
                }
                row("") {
                    HStack(spacing: 10) {
                        Button("Clear All History…") {
                            model.history.clearAll()
                            model.showToast("History cleared")
                        }
                        .buttonStyle(.glass)
                        Text(entryCountLabel)
                            .font(Theme.font(11.5))
                            .foregroundStyle(Theme.label3)
                    }
                }
            }
            .opacity(settings.historyEnabled ? 1 : 0.4)
            .disabled(!settings.historyEnabled)
            .animation(.easeOut(duration: 0.18), value: settings.historyEnabled)
        }
    }

    private var entryCountLabel: String {
        let n = model.history.entries.count
        return n == 1 ? "1 entry stored" : "\(n) entries stored"
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ok)
                Text(model.capabilities.runsOnDevice ? "Everything runs on this Mac." : "Only prompts leave your Mac.").font(Theme.font(13.5, .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            HairlineDivider().padding(.leading, 12)

            ForEach(Array(privacyPoints.enumerated()), id: \.offset) { i, point in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.ok)
                        .padding(.top, 2)
                    Text(point)
                        .font(Theme.font(12.5))
                        .foregroundStyle(Theme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                if i < privacyPoints.count - 1 {
                    HairlineDivider().padding(.leading, 12)
                }
            }
        }
        .groupedBox()
    }

    private var privacyPoints: [String] {
        PrivacyCopy.points(
            for: model.capabilities,
            watchingSelection: model.isWatchingSelection
        )
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 10) {
            BrandMark(size: 46)
                .padding(.bottom, 2)
            Text("PromptBar").font(Theme.font(17, .semibold))
            Text("Version \(Self.version) · prompt compiler")
                .font(Theme.font(12))
                .foregroundStyle(Theme.label2)
            Text("Turn rough thoughts into prompts that work. Powered by \(model.capabilities.providerName).")
                .font(Theme.font(12.5))
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Row helper

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Theme.font(13))
                .foregroundStyle(Theme.label2)
                .frame(width: labelColumn, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// Adds a running app to the history exclusion list.
private struct AddExcludedAppMenu: View {
    @Bindable var settings: AppSettings

    private var candidates: [ExcludedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return ExcludedApp(bundleID: id, name: name)
            }
            .filter { c in !settings.excludedApps.contains { $0.bundleID == c.bundleID } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu {
            if candidates.isEmpty {
                Text("No other running apps")
            } else {
                ForEach(candidates) { app in
                    Button(app.name) { settings.excludedApps.append(app) }
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
                .font(Theme.font(11.5))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .fixedSize()
    }
}

private extension SettingsTab {
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .history: "clock"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }
}
