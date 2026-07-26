import Testing
import Foundation
import AppKit
@testable import PromptBar

/// Builds a view model wired entirely to substitutable adapters.
@MainActor
private func makeModel(
    clipboardText: String? = nil,
    failure: EnhancementFailure? = nil,
    historyEnabled: Bool = false
) -> (PromptBarViewModel, StaticPromptModel, NSPasteboard) {
    let pb = NSPasteboard.withUniqueName()
    pb.clearContents()
    if let clipboardText { pb.setString(clipboardText, forType: .string) }

    let defaults = UserDefaults(suiteName: "promptbar-vm-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    settings.historyEnabled = historyEnabled

    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("promptbar-vm-\(UUID().uuidString)")
    let engine = StaticPromptModel(forcedFailure: failure)

    let vm = PromptBarViewModel(
        model: engine,
        clipboard: ClipboardService(pasteboard: pb),
        settings: settings,
        history: HistoryStore(directory: dir)
    )
    return (vm, engine, pb)
}

@Suite("Prompt bar view model")
@MainActor
struct PromptBarViewModelTests {

    @Test("Clipboard text auto-generates and lands on a result")
    func autoGenerates() async {
        let (vm, _, _) = makeModel(clipboardText: "refactor this networking layer")
        vm.prepareForOpen()
        #expect(vm.phase == .generating)
        await vm.settle()
        #expect(vm.phase == .result)
        #expect(vm.bundle?.suggestions.count == 3)
        #expect(vm.selectedStyle == .balanced)
    }

    @Test("An empty clipboard opens the manual editor instead")
    func manualEntry() async {
        let (vm, _, _) = makeModel(clipboardText: nil)
        vm.prepareForOpen()
        #expect(vm.phase == .input)
        #expect(vm.rawInput.isEmpty)
    }

    @Test("Over-long input is refused before the model is called")
    func refusesTooLong() async {
        let (vm, _, _) = makeModel()
        vm.prepareForOpen()
        vm.rawInput = String(repeating: "a", count: 5_000)
        vm.generateFromInput()
        #expect(vm.phase == .failure(.inputTooLong))
    }

    @Test("A provider failure surfaces as that failure phase")
    func surfacesFailure() async {
        let (vm, _, _) = makeModel(clipboardText: "hello", failure: .modelDownloading)
        vm.prepareForOpen()
        await vm.settle()
        #expect(vm.phase == .failure(.modelDownloading))
    }

    @Test("Copy writes the selected variant and asks the panel to close")
    func copyAndClose() async {
        let (vm, _, pb) = makeModel(clipboardText: "review this code")
        var closed = false
        var toast: String?
        vm.onRequestClose = { closed = true }
        vm.onToast = { toast = $0 }

        vm.prepareForOpen()
        await vm.settle()
        vm.select(.structured)
        vm.copySelectedAndClose()

        #expect(pb.string(forType: .string) == vm.bundle?.suggestion(for: .structured)?.prompt)
        #expect(closed)
        #expect(toast == "Enhanced prompt copied")
    }

    @Test("Editing a variant does not regenerate and is kept per style")
    func editingIsLocal() async {
        let (vm, _, _) = makeModel(clipboardText: "review this code")
        vm.prepareForOpen()
        await vm.settle()
        let original = vm.currentPromptText

        vm.beginEditing()
        vm.currentPromptText = "my own wording"
        #expect(vm.phase == .result)          // no regeneration
        #expect(vm.currentStyleWasEdited)

        vm.select(.minimal)
        #expect(!vm.currentStyleWasEdited)    // edit did not bleed across styles
        vm.select(.balanced)
        #expect(vm.currentPromptText == "my own wording")
        #expect(original != "my own wording")
    }

    @Test("History records only when enabled")
    func historyGate() async {
        let (off, _, _) = makeModel(clipboardText: "review this code", historyEnabled: false)
        off.prepareForOpen()
        await off.settle()
        off.copySelectedAndClose()
        #expect(off.history.entries.isEmpty)

        let (on, _, _) = makeModel(clipboardText: "review this code", historyEnabled: true)
        on.prepareForOpen()
        await on.settle()
        on.copySelectedAndClose()
        #expect(on.history.entries.count == 1)
        #expect(on.history.entries.first?.original == "review this code")
    }

    @Test("Excluded source apps are never recorded")
    func excludedApp() async {
        let (vm, _, _) = makeModel(clipboardText: "review this code", historyEnabled: true)
        vm.settings.excludedApps = [ExcludedApp(bundleID: "com.apple.Notes", name: "Notes")]
        vm.sourceBundleID = "com.apple.Notes"
        vm.prepareForOpen()
        await vm.settle()
        vm.copySelectedAndClose()
        #expect(vm.history.entries.isEmpty)
    }

    @Test("Instant Enhance replaces the clipboard and keeps a restore point")
    func instantEnhance() async {
        let (vm, _, pb) = makeModel(clipboardText: "review this code")
        var toast: String?
        vm.onToast = { toast = $0 }

        await vm.instantEnhance()
        let enhanced = pb.string(forType: .string)
        #expect(enhanced != "review this code")
        #expect(toast?.contains("restore") == true)
        #expect(vm.canRestoreClipboard)

        vm.restoreClipboard()
        #expect(pb.string(forType: .string) == "review this code")
    }

    @Test("Settings opened as root closes the panel when dismissed")
    func settingsAsRoot() async {
        let (vm, _, _) = makeModel()
        var closed = false
        vm.onRequestClose = { closed = true }
        vm.prepareForOpen()

        vm.openSettings(asRoot: true)
        #expect(vm.isShowingSettings)
        vm.closeSettings()
        #expect(!vm.isShowingSettings)
        #expect(closed)
    }

    @Test("Settings opened over a result returns to the result")
    func settingsOverResult() async {
        let (vm, _, _) = makeModel(clipboardText: "review this code")
        var closed = false
        vm.onRequestClose = { closed = true }
        vm.prepareForOpen()
        await vm.settle()

        vm.openSettings()
        vm.closeSettings()
        #expect(!vm.isShowingSettings)
        #expect(!closed)
        #expect(vm.phase == .result)
    }

    @Test("Limits and provider description come from the model, not a constant")
    func capabilitiesDriveLimits() async {
        let pb = NSPasteboard.withUniqueName()
        let defaults = UserDefaults(suiteName: "promptbar-cap-\(UUID().uuidString)")!
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("promptbar-cap-\(UUID().uuidString)")
        let big = StaticPromptModel(capabilities: ModelCapabilities(
            providerName: "Roomy Cloud",
            runsOnDevice: false,
            inputLimits: InputLimits(soft: 100_000, hard: 200_000)
        ))
        let vm = PromptBarViewModel(
            model: big,
            clipboard: ClipboardService(pasteboard: pb),
            settings: AppSettings(defaults: defaults),
            history: HistoryStore(directory: dir)
        )
        vm.rawInput = String(repeating: "a", count: 5_000)
        #expect(vm.inputLimitState == .ok)          // would be .tooLong on-device
        #expect(!vm.capabilities.runsOnDevice)
        #expect(vm.capabilities.providerName == "Roomy Cloud")
    }
}
