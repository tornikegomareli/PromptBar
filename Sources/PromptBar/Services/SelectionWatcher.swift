import AppKit
import ApplicationServices

/// Text the user has selected in another app, plus where it is on screen.
struct TextSelection: Equatable, Sendable {
    var text: String
    /// Screen rect of the selection in Cocoa (bottom-left origin) coordinates.
    /// `nil` when the app exposes the text but not its bounds, in which case
    /// the popup falls back to the pointer.
    var rect: CGRect?
}

/// Decides which selections are worth offering to compile. Pure and
/// synchronous so the judgement is testable without Accessibility access.
enum SelectionPolicy {
    /// Below this a selection is almost always an accident — a word, a variable
    /// name, a stray double-click. Popping a chip for those is the fastest way
    /// to make the feature feel like spyware that also nags.
    static let minimumLength = 12

    /// Elements whose contents must never be read, whatever the user enabled.
    ///
    /// A password field is identified by its *subrole* — its role is the plain
    /// `AXTextField`, so checking the role alone silently reads passwords.
    /// Matches `kAXSecureTextFieldSubrole` / `NSAccessibilitySecureTextFieldSubrole`.
    static let forbiddenSubroles: Set<String> = ["AXSecureTextField"]

    static func shouldOffer(_ raw: String, limits: InputLimits) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minimumLength else { return false }
        // Pure punctuation, hex blobs and number columns are not prompts.
        guard text.contains(where: \.isLetter) else { return false }
        // No point offering to compile something the provider will refuse.
        return limits.state(for: text) != .tooLong
    }

    static func isForbidden(subrole: String?) -> Bool {
        guard let subrole else { return false }
        return forbiddenSubroles.contains(subrole)
    }
}

/// Whether the app may use the Accessibility APIs the selection popup needs.
enum AccessibilityAuthorization {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt with the deep link into Privacy & Security.
    /// Returns the trust state *before* the prompt, so callers can tell whether
    /// they should wait for the user to come back.
    /// The literal key rather than `kAXTrustedCheckOptionPrompt`: that symbol is
    /// a mutable global, which Swift 6 rejects as not concurrency-safe.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    @discardableResult
    static func request() -> Bool {
        AXIsProcessTrustedWithOptions([promptOptionKey: true] as CFDictionary)
    }

    static func openSettingsPane() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Watches for text selections in *other* apps and reports ones worth acting
/// on, so PromptBar can offer to compile them where they were written.
///
/// macOS publishes no "selection changed" notification, so this is the same
/// shape every popup utility uses: notice the mouse coming up, then ask the
/// focused element what it has selected.
///
/// Deliberately **not** implemented here: the synthetic-⌘C fallback that reads
/// selections out of apps which expose no Accessibility text (many Electron
/// apps). That fallback has to write to the pasteboard and press keys on the
/// user's behalf, which contradicts what Settings › Privacy promises. Apps
/// without AX text simply do not get a chip.
@MainActor
final class SelectionWatcher {
    /// Reports a selection worth offering. Never called while `suppress()` says so.
    var onSelection: ((TextSelection) -> Void)?
    /// The user clicked elsewhere — take any popup down.
    var onDismiss: (() -> Void)?
    /// Asked before reading anything, so the owner can veto: panel already
    /// open, source app excluded, our own window focused.
    var suppress: (() -> Bool)?

    private let limits: () -> InputLimits
    private var upMonitor: Any?
    private var downMonitor: Any?
    private var pending: Task<Void, Never>?

    /// AppKit needs a beat to commit the selection after the mouse comes up;
    /// reading immediately returns the *previous* selection in several apps.
    private let settleDelay = Duration.milliseconds(120)

    init(limits: @escaping () -> InputLimits = { .conservative }) {
        self.limits = limits
    }

    var isRunning: Bool { upMonitor != nil }

    func start() {
        guard !isRunning, AccessibilityAuthorization.isTrusted else { return }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRead() }
        }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismiss?() }
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        for monitor in [upMonitor, downMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        upMonitor = nil
        downMonitor = nil
    }

    // No `deinit` teardown: a nonisolated deinit cannot touch these
    // non-Sendable monitor tokens under Swift 6, and the watcher is owned by the
    // app shell for the whole process lifetime. `stop()` is the real teardown.

    private func scheduleRead() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.settleDelay)
            guard !Task.isCancelled else { return }
            self.readSelection()
        }
    }

    private func readSelection() {
        guard suppress?() != true else { return }
        guard let selection = Self.currentSelection(limits: limits()) else {
            onDismiss?()
            return
        }
        onSelection?(selection)
    }

    // MARK: - Accessibility reads

    /// The focused element's selected text, or nil when there is nothing worth
    /// offering — including when the element refuses to say.
    static func currentSelection(limits: InputLimits) -> TextSelection? {
        let system = AXUIElementCreateSystemWide()
        guard let focused: AXUIElement = copy(system, kAXFocusedUIElementAttribute) else { return nil }

        let subrole: String? = copy(focused, kAXSubroleAttribute)
        guard !SelectionPolicy.isForbidden(subrole: subrole) else { return nil }

        guard let text: String = copy(focused, kAXSelectedTextAttribute),
              SelectionPolicy.shouldOffer(text, limits: limits) else { return nil }

        return TextSelection(text: text, rect: selectionRect(of: focused))
    }

    /// Screen rect of the selected range, converted to Cocoa coordinates.
    private static func selectionRect(of element: AXUIElement) -> CGRect? {
        guard let rangeValue: AXValue = copy(element, kAXSelectedTextRangeAttribute) else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &bounds
        ) == .success, let bounds else { return nil }

        // `as? AXValue` always succeeds for any CF type, so it proves nothing —
        // compare the actual CFTypeID before treating this as an AXValue.
        guard CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        let boundsValue = unsafeDowncast(bounds as AnyObject, to: AXValue.self)

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else {
            return nil
        }
        return flipToCocoa(rect)
    }

    /// Accessibility reports rects with the origin at the top-left of the
    /// primary display; `NSWindow` places them from the bottom-left. Skipping
    /// this puts the popup mirrored to the far side of the screen.
    private static func flipToCocoa(_ rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let primary else { return rect }
        return CGRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Typed `AXUIElementCopyAttributeValue`, which is otherwise four lines of
    /// `CFTypeRef` juggling at every call site.
    private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
