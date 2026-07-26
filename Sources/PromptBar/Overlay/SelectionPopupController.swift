import AppKit
import SwiftUI

/// A panel that must never take focus. Activating PromptBar would deselect the
/// text in the source app and invalidate the focused Accessibility element the
/// selection was just read from — the popup would destroy its own reason to
/// exist. This is the opposite of `KeyablePanel`.
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the compile chip beside a selection and reports taps.
///
/// The chip is only a shortcut into the main panel. It deliberately does not
/// compile in place: the variants and the missing-context chips are the product,
/// and silently replacing a user's selection with one unreviewed variant would
/// be both destructive and a worse experience than the panel it bypasses.
@MainActor
final class SelectionPopupController {
    /// The user wants this text compiled.
    var onCompile: ((String) -> Void)?

    private var panel: NonActivatingPanel?
    private var selection: TextSelection?
    private var dismissTask: Task<Void, Never>?

    /// A chip that outlives the glance it belongs to turns into litter on the
    /// screen, and there is no focus event to retire it — the app is never active.
    private let lifetime = Duration.seconds(4)

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(for selection: TextSelection) {
        self.selection = selection
        let panel = panel ?? makePanel()
        self.panel = panel

        position(panel, near: selection.rect)
        // `orderFrontRegardless`, never `makeKeyAndOrderFront`: the source app
        // stays frontmost and keeps its selection.
        panel.orderFrontRegardless()
        scheduleDismiss()
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        selection = nil
    }

    // MARK: - Panel

    private func makePanel() -> NonActivatingPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // the chip draws its own
        panel.level = .popUpMenu         // above the source app's windows
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = NSHostingController(
            rootView: SelectionPopupView { [weak self] in self?.compile() }
        )
        return panel
    }

    private func compile() {
        guard let text = selection?.text else { return }
        hide()
        onCompile?(text)
    }

    /// Sits just above the selection, or at the pointer when the app exposed no
    /// bounds. Clamped so a selection at a screen edge cannot push it off.
    private func position(_ panel: NSPanel, near rect: CGRect?) {
        let size = panel.frame.size
        let gap: CGFloat = 6

        var origin: CGPoint
        if let rect {
            origin = CGPoint(x: rect.midX - size.width / 2, y: rect.maxY + gap)
        } else {
            let mouse = NSEvent.mouseLocation
            origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y + gap * 2)
        }

        let screen = screenContaining(origin) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            // Flip below the selection when there is no room above it.
            if origin.y + size.height > visible.maxY, let rect {
                origin.y = rect.minY - size.height - gap
            }
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.lifetime)
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }
}
