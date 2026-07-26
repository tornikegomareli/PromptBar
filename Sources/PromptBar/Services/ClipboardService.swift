import AppKit

/// Plain-text pasteboard access (PRD §18). Deliberately *not* a general
/// clipboard manager — it reads and writes text and remembers the single
/// previous value so the user can restore it after an Instant Enhance.
@MainActor
final class ClipboardService {
    private let pasteboard: NSPasteboard
    private var restoreValue: String?
    private var lastWritten: String?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Current plain-text clipboard contents, trimmed to nil when empty.
    func readText() -> String? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    /// Whether there is a value `restorePrevious()` could put back.
    var hasRestorePoint: Bool { restoreValue != nil }

    /// Write text, stashing the prior value so `restorePrevious()` can undo it.
    ///
    /// Repeated writes keep the *original* restore point: otherwise a second
    /// Instant Enhance would make "restore" hand back the first enhancement
    /// rather than the user's own text.
    func write(_ text: String) {
        let current = pasteboard.string(forType: .string)
        if current != lastWritten {
            restoreValue = current
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastWritten = text
    }

    /// Write without capturing a restore point (normal Copy & Close).
    func replace(with text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    func restorePrevious() -> Bool {
        guard let restoreValue else { return false }
        pasteboard.clearContents()
        pasteboard.setString(restoreValue, forType: .string)
        self.restoreValue = nil
        self.lastWritten = nil
        return true
    }
}
