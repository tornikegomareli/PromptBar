import AppKit
import SwiftUI

/// A small, self-dismissing confirmation toast (PRD §6.1 "Enhanced prompt copied").
@MainActor
final class ToastPresenter {
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: Duration = .seconds(1.6)) {
        dismissTask?.cancel()

        let toast = ToastView(message: message)
        let host = NSHostingView(rootView: toast)
        host.layout()
        let size = host.fittingSize

        let window = self.window ?? makeWindow()
        self.window = window
        window.contentView = host
        window.setContentSize(size)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - size.width / 2
            let y = frame.maxY - (frame.height * 0.18) - size.height / 2
            window.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        }

        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { window.orderOut(nil) }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return window
    }
}

private struct ToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white, Theme.ok)
                .symbolRenderingMode(.palette)
            Text(message)
                .font(Theme.font(13))
                .foregroundStyle(Theme.label)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 11))
        .fixedSize()
    }
}
