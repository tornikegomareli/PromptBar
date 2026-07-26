import AppKit
import SwiftUI

/// A borderless panel that can become key so text fields inside it accept
/// keyboard focus (PRD §18 OverlayWindowController).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the floating panel lifecycle (PRD §18). Appears on the active display,
/// joins all spaces, floats above full-screen apps, becomes key on open, and
/// restores focus to the previously-active app after it closes.
@MainActor
final class OverlayWindowController {
    private let viewModel: PromptBarViewModel
    private var panel: KeyablePanel?
    private let toast = ToastPresenter()
    private var previousApp: NSRunningApplication?
    private var focusLossObserver: Any?
    private var pendingDismissTask: Task<Void, Never>?

    init(viewModel: PromptBarViewModel) {
        self.viewModel = viewModel
        viewModel.onRequestClose = { [weak self] in self?.hide() }
        viewModel.onToast = { [weak self] message in self?.toast.show(message) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show(ingestClipboard: Bool = true) {
        previousApp = NSWorkspace.shared.frontmostApplication
        viewModel.sourceBundleID = previousApp?.bundleIdentifier
        viewModel.prepareForOpen(ingestClipboard: ingestClipboard)

        let panel = panel ?? makePanel()
        self.panel = panel

        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        observeFocusLoss()
    }

    /// - Parameter restoringFocus: only true for an *explicit* dismissal
    ///   (Copy & Close, Esc, Cancel). When the user simply switched to another
    ///   app, re-activating the previous app would yank them away from the
    ///   window they just clicked.
    func hide(restoringFocus: Bool = true) {
        removeFocusObserver()
        panel?.orderOut(nil)
        if restoringFocus,
           let previousApp,
           previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    // MARK: - Panel construction

    private static var windowWidth: CGFloat { PanelMetrics.width }

    private func makePanel() -> KeyablePanel {
        let contentRect = NSRect(x: 0, y: 0, width: Self.windowWidth, height: 520)
        let panel = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Let AppKit draw the soft macOS window shadow beneath the glass panel.
        panel.hasShadow = true
        panel.level = .floating
        // NOTE: .canJoinAllSpaces must not be combined with .moveToActiveSpace —
        // the two are contradictory and wedge window creation.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = windowDelegate

        // The content has a definite intrinsic size, so let the hosting view
        // size the window to it — the panel hugs its content.
        let host = NSHostingView(rootView: PromptBarPanelView(model: viewModel))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        return panel
    }

    /// Recenters the panel whenever its content size changes (mode switches).
    private lazy var windowDelegate = PanelDelegate { [weak self] in
        guard let self, let panel = self.panel else { return }
        self.position(panel)
    }

    private func position(_ panel: NSPanel) {
        let frame = activeScreen().visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - (frame.height * PanelMetrics.verticalAnchor) - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// The screen containing the active app's key window, else the mouse, else main.
    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    // MARK: - Focus loss

    /// Dismiss when the *app* deactivates (user switched to another app), not
    /// when the window merely resigns key. This lets in-panel menus (target
    /// picker, gear) open without the panel yanking itself closed — while a
    /// genuine click into another app still dismisses. Guarded during
    /// generation (PRD §18).
    private func observeFocusLoss() {
        removeFocusObserver()
        focusLossObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.viewModel.phase == .generating {
                    // Don't yank the panel away mid-generation — but remember to
                    // close once it finishes, otherwise the floating panel is
                    // stranded on top of every app with no further resign event.
                    self.dismissWhenGenerationEnds()
                } else {
                    self.hide(restoringFocus: false)
                }
            }
        }
    }

    /// Polls only until the in-flight generation settles, then closes if the
    /// user is still in another app.
    private func dismissWhenGenerationEnds() {
        guard pendingDismissTask == nil else { return }
        pendingDismissTask = Task { [weak self] in
            await self?.viewModel.settle()
            guard let self, !Task.isCancelled else { return }
            self.pendingDismissTask = nil
            if !NSApp.isActive, self.isVisible {
                self.hide(restoringFocus: false)
            }
        }
    }

    private func removeFocusObserver() {
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        if let focusLossObserver {
            NotificationCenter.default.removeObserver(focusLossObserver)
            self.focusLossObserver = nil
        }
    }
}

/// Recenters the panel when its content-driven size changes.
private final class PanelDelegate: NSObject, NSWindowDelegate {
    private let onResize: () -> Void
    init(onResize: @escaping () -> Void) { self.onResize = onResize }
    func windowDidResize(_ notification: Notification) { onResize() }
}
