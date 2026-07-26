import AppKit

/// Menu bar app shell (PRD §14). No persistent Dock icon (`.accessory`);
/// owns the status item, the global hotkey, and the overlay panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let history = HistoryStore()
    private let clipboard = ClipboardService()
    private let hotKeys = HotKeyService()
    private let model: PromptModel = AppleSystemPromptModel()

    private var viewModel: PromptBarViewModel!
    private var overlay: OverlayWindowController!
    private var statusItem: NSStatusItem!

    private let selectionPopup = SelectionPopupController()
    private var selectionWatcher: SelectionWatcher!
    private var grantWatchTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = PromptBarViewModel(
            model: model,
            clipboard: clipboard,
            settings: settings,
            history: history
        )
        overlay = OverlayWindowController(viewModel: viewModel)

        setUpStatusItem()
        registerHotKeys()
        setUpSelectionPopup()
    }

    // MARK: - Selection popup

    private func setUpSelectionPopup() {
        selectionWatcher = SelectionWatcher(limits: { [model] in model.capabilities.inputLimits })

        selectionWatcher.onSelection = { [weak self] selection in
            self?.selectionPopup.show(for: selection)
        }
        selectionWatcher.onDismiss = { [weak self] in
            self?.selectionPopup.hide()
        }
        // Read nothing when the panel is already up, when the selection is in
        // our own UI, or when the user has excluded the app it belongs to.
        selectionWatcher.suppress = { [weak self] in
            guard let self else { return true }
            if self.overlay.isVisible { return true }
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if front == Bundle.main.bundleIdentifier { return true }
            return self.settings.isExcluded(bundleID: front)
        }

        selectionPopup.onCompile = { [weak self] text in
            self?.overlay.show(with: text)
        }

        viewModel.onSelectionPopupChanged = { [weak self] _ in
            self?.syncSelectionWatcher()
        }
        syncSelectionWatcher()
    }

    /// Starts or stops watching to match the setting and the current grant.
    private func syncSelectionWatcher() {
        viewModel.refreshAccessibilityTrust()
        if viewModel.isWatchingSelection {
            selectionWatcher.start()
        } else {
            selectionWatcher.stop()
            selectionPopup.hide()
        }
        awaitAccessibilityGrant()
    }

    /// The user grants Accessibility in System Settings, outside this app, and
    /// may never come back to PromptBar's window — so nothing would otherwise
    /// tell us the feature can now start. Poll, but only while we are actually
    /// waiting on a grant, and give up rather than tick forever.
    private func awaitAccessibilityGrant() {
        guard settings.selectionPopupEnabled, !viewModel.isAccessibilityTrusted else { return }
        guard grantWatchTask == nil else { return }
        grantWatchTask = Task { [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                guard self.settings.selectionPopupEnabled else { break }
                if AccessibilityAuthorization.isTrusted {
                    self.grantWatchTask = nil
                    self.syncSelectionWatcher()
                    return
                }
            }
            self?.grantWatchTask = nil
        }
    }

    // MARK: - Status item & menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.statusBarGlyph()
            button.toolTip = "PromptBar — improve prompts"
        }
        statusItem.menu = buildMenu()
        statusItem.menu?.delegate = self
    }

    /// Rebuilds the menu each time it opens so Recent / profile ticks are fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        let fresh = buildMenu()
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    /// The 16pt monochrome bracket-→-arrow status-bar glyph (design handoff §9),
    /// drawn from the same path as the SwiftUI brand mark and set as a template.
    private static func statusBarGlyph() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let scale = 16.0 / 24.0
            let dx = (18.0 - 24.0 * scale) / 2
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: dx + x * scale, y: 16 - y * scale) // flip y
            }
            let path = NSBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // bracket
            path.move(to: pt(10, 5))
            path.line(to: pt(7.5, 5))
            path.appendArc(from: pt(5, 5), to: pt(5, 7.5), radius: 2.5 * scale)
            path.line(to: pt(5, 16.5))
            path.appendArc(from: pt(5, 19), to: pt(7.5, 19), radius: 2.5 * scale)
            path.line(to: pt(10, 19))
            // shaft
            path.move(to: pt(13.5, 12))
            path.line(to: pt(19, 12))
            // head
            path.move(to: pt(16, 9))
            path.line(to: pt(19, 12))
            path.line(to: pt(16, 15))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            withTitle: "Open PromptBar",
            action: #selector(openPanel),
            keyEquivalent: " "
        ).do {
            $0.keyEquivalentModifierMask = [.shift, .option]
            $0.target = self
        }

        menu.addItem(
            withTitle: "Instant Enhance Clipboard",
            action: #selector(instantEnhance),
            keyEquivalent: "e"
        ).do {
            $0.keyEquivalentModifierMask = [.shift, .option]
            $0.target = self
        }

        menu.addItem(
            withTitle: "Compile from Selection",
            action: #selector(toggleSelectionPopup),
            keyEquivalent: ""
        ).do {
            $0.target = self
            $0.state = viewModel.isWatchingSelection ? .on : .off
            // Distinguish "off" from "on but waiting on Accessibility", which
            // otherwise looks identical and reads as the toggle not working.
            if settings.selectionPopupEnabled && !viewModel.isAccessibilityTrusted {
                $0.title = "Compile from Selection — needs Accessibility"
            }
        }

        if viewModel.canRestoreClipboard {
            menu.addItem(
                withTitle: "Restore Clipboard",
                action: #selector(restoreClipboard),
                keyEquivalent: ""
            ).do { $0.target = self }
        }

        menu.addItem(.separator())

        // Profiles submenu — sets the default profile applied on open.
        let profilesItem = NSMenuItem(title: "Default Profile", action: nil, keyEquivalent: "")
        let profiles = NSMenu()
        for profile in TargetProfile.allCases {
            let item = NSMenuItem(
                title: profile.displayName,
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = profile.rawValue
            item.state = (profile == settings.defaultProfile) ? .on : .off
            profiles.addItem(item)
        }
        profilesItem.submenu = profiles
        menu.addItem(profilesItem)

        // Recent enhancements (only when history is enabled and non-empty).
        let recent = settings.historyEnabled ? history.recent(2) : []
        if !recent.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for entry in recent {
                let title = entry.original.count > 38
                    ? String(entry.original.prefix(38)) + "…"
                    : entry.original
                menu.addItem(withTitle: title, action: #selector(reuseRecent(_:)), keyEquivalent: "")
                    .do {
                        $0.target = self
                        $0.representedObject = entry.enhanced
                        $0.indentationLevel = 1
                    }
            }
        }

        menu.addItem(.separator())

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .do { $0.target = self }
        menu.addItem(withTitle: "About PromptBar", action: #selector(showAbout), keyEquivalent: "")
            .do { $0.target = self }
        menu.addItem(
            withTitle: "Quit PromptBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        return menu
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        if hotKeys.register(.openPanel, handler: { [weak self] in self?.overlay.toggle() }) == nil {
            NSLog("PromptBar: failed to register the open-panel global hotkey.")
        }
        if hotKeys.register(.instantEnhance, handler: { [weak self] in self?.instantEnhance() }) == nil {
            NSLog("PromptBar: failed to register the instant-enhance global hotkey.")
        }
    }

    // MARK: - Actions

    @objc private func openPanel() {
        overlay.show()
    }

    /// Instant Enhance runs without showing the panel; the toast is the only UI.
    @objc private func instantEnhance() {
        Task { await viewModel.instantEnhance() }
    }

    @objc private func toggleSelectionPopup() {
        let enabling = !settings.selectionPopupEnabled
        viewModel.setSelectionPopupEnabled(enabling)
        if enabling, !viewModel.isAccessibilityTrusted {
            viewModel.openAccessibilitySettings()
        }
    }

    @objc private func restoreClipboard() {
        viewModel.restoreClipboard()
    }

    @objc private func openSettings() {
        overlay.show(ingestClipboard: false)
        viewModel.openSettings(asRoot: true)
    }

    /// Re-copies a previously enhanced prompt straight from the menu.
    @objc private func reuseRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        clipboard.replace(with: text)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let profile = TargetProfile(rawValue: raw) else { return }
        settings.defaultProfile = profile
        // No need to swap the menu — `menuNeedsUpdate` rebuilds it on open, and
        // reassigning it here used to drop the delegate.
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "PromptBar",
            .init(rawValue: "Copyright"): "Turn rough thoughts into prompts that work.",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension NSMenuItem {
    /// Tiny helper for inline configuration.
    @discardableResult
    func `do`(_ body: (NSMenuItem) -> Void) -> NSMenuItem {
        body(self)
        return self
    }
}
