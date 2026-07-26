import Testing
import Foundation
import AppKit
@testable import PromptBar

@Suite("Selection policy")
struct SelectionPolicyTests {
    private let limits = InputLimits.conservative

    @Test("A real sentence is worth offering")
    func offersProse() {
        #expect(SelectionPolicy.shouldOffer("review this networking layer for races", limits: limits))
    }

    @Test("Short selections are ignored")
    func ignoresShort() {
        // A double-click on one word is the most common accidental selection.
        #expect(!SelectionPolicy.shouldOffer("refactor", limits: limits))
        #expect(!SelectionPolicy.shouldOffer("", limits: limits))
        #expect(!SelectionPolicy.shouldOffer("   \n  ", limits: limits))
    }

    @Test("Selections with no letters are ignored")
    func ignoresNonProse() {
        #expect(!SelectionPolicy.shouldOffer("1234567890123456", limits: limits))
        #expect(!SelectionPolicy.shouldOffer("{}[]();{}[]();...", limits: limits))
    }

    @Test("Selections the provider would refuse are not offered")
    func ignoresTooLong() {
        let huge = String(repeating: "a", count: limits.hard + 1)
        #expect(!SelectionPolicy.shouldOffer(huge, limits: limits))
    }

    /// A password field's *role* is the ordinary `AXTextField`; only its subrole
    /// marks it secure. Checking the role alone would read passwords.
    @Test("Secure fields are refused by subrole")
    func refusesSecureFields() {
        #expect(SelectionPolicy.isForbidden(subrole: "AXSecureTextField"))
        #expect(!SelectionPolicy.isForbidden(subrole: "AXSearchField"))
        #expect(!SelectionPolicy.isForbidden(subrole: nil))
    }
}

@Suite("Selection popup settings")
@MainActor
struct SelectionPopupSettingsTests {

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "promptbar-sel-\(UUID().uuidString)")!)
    }

    @Test("The popup is off until asked for")
    func defaultsOff() {
        #expect(makeSettings().selectionPopupEnabled == false)
    }

    @Test("The choice persists")
    func persists() {
        let name = "promptbar-sel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        AppSettings(defaults: defaults).selectionPopupEnabled = true
        #expect(AppSettings(defaults: defaults).selectionPopupEnabled)
    }
}

@Suite("Opening from a selection")
@MainActor
struct SelectionOpenTests {

    private func makeModel() -> (PromptBarViewModel, AppSettings) {
        let defaults = UserDefaults(suiteName: "promptbar-selopen-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("promptbar-selopen-\(UUID().uuidString)")
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        pb.setString("CLIPBOARD TEXT THAT MUST NOT BE USED", forType: .string)
        let vm = PromptBarViewModel(
            model: StaticPromptModel(),
            clipboard: ClipboardService(pasteboard: pb),
            settings: settings,
            history: HistoryStore(directory: dir)
        )
        return (vm, settings)
    }

    @Test("The selected text is enhanced, not the clipboard")
    func usesSelectionNotClipboard() async {
        let (vm, _) = makeModel()
        vm.prepareForOpen(with: "review this networking layer for races")
        #expect(vm.rawInput == "review this networking layer for races")
        #expect(vm.phase == .generating)
        await vm.settle()
        #expect(vm.phase == .result)
    }

    /// "Excluded" has to mean the text is never read, matching what the
    /// clipboard path already guarantees — not merely left out of history.
    @Test("An excluded source app is never enhanced")
    func honoursExcludedApps() async {
        let (vm, settings) = makeModel()
        settings.excludedApps = [ExcludedApp(bundleID: "com.example.vault", name: "Vault")]
        vm.sourceBundleID = "com.example.vault"
        vm.prepareForOpen(with: "a secret note the user selected in a vault")
        #expect(vm.phase == .input)
        #expect(vm.rawInput.isEmpty)
    }

    @Test("Watching requires both the toggle and the grant")
    func watchingNeedsBoth() {
        let (vm, settings) = makeModel()
        settings.selectionPopupEnabled = false
        #expect(vm.isWatchingSelection == false)
        settings.selectionPopupEnabled = true
        // Trust is whatever the test process actually has; the invariant is that
        // the flag alone is never sufficient.
        #expect(vm.isWatchingSelection == vm.isAccessibilityTrusted)
    }
}

@Suite("Privacy copy")
@MainActor
struct PrivacyCopyTests {
    private let capabilities = StaticPromptModel().capabilities

    @Test("Selection watching is disclosed when it is on")
    func disclosesWatching() {
        let points = PrivacyCopy.points(for: capabilities, watchingSelection: true)
        let joined = points.joined(separator: " ").lowercased()
        #expect(joined.contains("select"))
        // The exemptions are the reassurance that makes the disclosure usable.
        #expect(joined.contains("password"))
    }

    /// The privacy page must not describe a watcher that is not running.
    @Test("Nothing about selections is claimed when it is off")
    func silentWhenOff() {
        let points = PrivacyCopy.points(for: capabilities, watchingSelection: false)
        #expect(!points.joined(separator: " ").lowercased().contains("selection popup"))
    }

    /// The v1 watcher reads Accessibility text only — it never falls back to
    /// synthesising ⌘C — so this promise stays true with the popup on.
    @Test("The clipboard promise survives the popup")
    func clipboardPromiseHolds() {
        for watching in [true, false] {
            let joined = PrivacyCopy.points(for: capabilities, watchingSelection: watching)
                .joined(separator: " ")
            #expect(joined.contains("only when you ask"))
        }
    }
}
