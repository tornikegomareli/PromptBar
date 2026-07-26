import AppKit
import Observation

/// Drives the floating panel (PRD §6–§8). Owns the input → enhancement →
/// copy transformation and nothing else — no chat, no history transcript.
@MainActor
@Observable
final class PromptBarViewModel {
    /// High-level UI phase. The panel appears *before* generation begins
    /// (PRD §26), so `input` and `generating` both show immediately.
    enum Phase: Equatable {
        case input          // manual entry / empty clipboard
        case generating
        case result
        case failure(EnhancementFailure)
    }

    // Inputs
    var rawInput: String = "" {
        didSet { lint = rawInput.isEmpty ? nil : PromptLinter.lint(rawInput) }
    }
    var profile: TargetProfile = .auto
    var selectedStyle: SuggestionStyle = .balanced

    // Derived / output
    private(set) var phase: Phase = .input
    private(set) var bundle: EnhancementBundle?
    private(set) var lint: PromptLintResult?
    private(set) var isEditingResult = false

    /// Local edits keyed by style. Editing never triggers regeneration (§7).
    private var editedPrompts: [SuggestionStyle: String] = [:]
    /// Snapshot taken when a regeneration starts, so Cancel can put the user's
    /// edits back instead of silently discarding them.
    private var editsBeforeRegenerate: [SuggestionStyle: String]?
    /// Guards against recording the same delivery twice.
    private var lastRecordedFingerprint: String?

    /// Limits come from the provider, not a global constant.
    var inputLimits: InputLimits { model.capabilities.inputLimits }
    var inputLimitState: InputLimits.State { inputLimits.state(for: rawInput) }
    var capabilities: ModelCapabilities { model.capabilities }

    /// What the user can do about a failure — answered by the provider.
    func recovery(for failure: EnhancementFailure) -> RecoveryAction {
        model.recovery(for: failure)
    }

    // MARK: - Settings presentation

    /// Settings replaces the panel body when shown (design handoff §6).
    /// Bumped on every open so the view can re-assert focus; `.onAppear` fires
    /// only once because the panel is reused across opens.
    private(set) var openToken = 0

    private(set) var isShowingSettings = false
    var settingsTab: SettingsTab = .general
    /// True when the panel was opened *for* settings, so closing it closes the panel.
    private var settingsIsRoot = false

    // Collaborators
    private let model: PromptModel
    private let clipboard: ClipboardService
    let settings: AppSettings
    let history: HistoryStore

    /// Bundle ID of the app the user came from, used to honour excluded apps.
    var sourceBundleID: String?

    // Side-effect callbacks owned by the window controller.
    var onRequestClose: (() -> Void)?
    var onToast: ((String) -> Void)?

    private var generationTask: Task<Void, Never>?
    private var instantTask: Task<Void, Never>?

    /// Lets tests await the in-flight enhancement instead of polling.
    func settle() async { await generationTask?.value }

    init(
        model: PromptModel,
        clipboard: ClipboardService,
        settings: AppSettings,
        history: HistoryStore
    ) {
        self.model = model
        self.clipboard = clipboard
        self.settings = settings
        self.history = history
        history.prune(using: settings.retention)
    }

    // MARK: - Settings

    func openSettings(asRoot: Bool = false) {
        settingsIsRoot = asRoot
        isShowingSettings = true
        settings.refreshLaunchAtLogin()
        // Accessibility can be granted or revoked outside the app, so the
        // toggle's helper text has to be re-derived every time Settings opens.
        refreshAccessibilityTrust()
    }

    /// Leaves settings, returning to the panel body — or closing the panel when
    /// settings was the reason it opened.
    func closeSettings() {
        isShowingSettings = false
        if settingsIsRoot {
            settingsIsRoot = false
            requestClose()
        }
    }

    func showToast(_ message: String) { onToast?(message) }

    // MARK: - Lifecycle

    /// Called each time the panel opens. Uses clipboard text when suitable,
    /// otherwise drops into the manual editor (PRD §6.1 / §6.2).
    /// - Parameter ingestClipboard: `false` when the panel is being opened for
    ///   Settings — asking for Settings must not read the pasteboard or start
    ///   an inference (PromptBar promises it reads the pasteboard only when
    ///   you ask).
    func prepareForOpen(ingestClipboard: Bool = true) {
        reset()
        openToken &+= 1

        // Never ingest from an excluded app: "excluded" has to mean the text is
        // not read at all, not merely that it is left out of history.
        let excludedSource = settings.isExcluded(bundleID: sourceBundleID)

        if ingestClipboard, !excludedSource,
           let text = clipboard.readText(), inputLimits.state(for: text) != .empty {
            rawInput = text
            startGeneration()
        } else {
            phase = .input
        }
        // Warm on every open — the clipboard path is the one that generates
        // immediately, so it needs this most.
        Task { [model] in await model.prewarm() }
    }

    /// Called when the panel opens for text the user selected elsewhere. The
    /// text is already in hand, so this never touches the pasteboard.
    func prepareForOpen(with text: String) {
        reset()
        openToken &+= 1
        guard !settings.isExcluded(bundleID: sourceBundleID),
              inputLimitState(of: text) != .empty else {
            phase = .input
            return
        }
        rawInput = text
        startGeneration()
        Task { [model] in await model.prewarm() }
    }

    private func inputLimitState(of text: String) -> InputLimits.State {
        inputLimits.state(for: text)
    }

    // MARK: - Selection popup

    /// Set by the app shell so flipping the toggle starts or stops the watcher
    /// immediately, rather than at the next launch.
    var onSelectionPopupChanged: ((Bool) -> Void)?

    var isAccessibilityTrusted: Bool = AccessibilityAuthorization.isTrusted

    func refreshAccessibilityTrust() {
        isAccessibilityTrusted = AccessibilityAuthorization.isTrusted
    }

    /// Turning the popup on is also when we ask for Accessibility — requesting
    /// it at launch would prompt people who never wanted the feature.
    func setSelectionPopupEnabled(_ enabled: Bool) {
        settings.selectionPopupEnabled = enabled
        if enabled, !AccessibilityAuthorization.isTrusted {
            AccessibilityAuthorization.request()
        }
        refreshAccessibilityTrust()
        onSelectionPopupChanged?(enabled)
    }

    func openAccessibilitySettings() {
        AccessibilityAuthorization.openSettingsPane()
    }

    /// True when the popup is switched on *and* actually able to run.
    var isWatchingSelection: Bool {
        settings.selectionPopupEnabled && isAccessibilityTrusted
    }

    private func reset() {
        generationTask?.cancel()
        generationTask = nil
        rawInput = ""
        isShowingSettings = false
        settingsIsRoot = false
        profile = settings.defaultProfile
        selectedStyle = settings.defaultStyle
        bundle = nil
        isEditingResult = false
        editedPrompts.removeAll()
        editsBeforeRegenerate = nil
        lastRecordedFingerprint = nil
        phase = .input
    }

    // MARK: - Generation

    /// Generate from the current manual input (⌘Return in `input` phase).
    func generateFromInput() {
        guard !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        startGeneration()
    }

    func regenerate() {
        // Kept until the new bundle actually arrives, so Cancel restores them.
        editsBeforeRegenerate = editedPrompts
        startGeneration()
    }

    private func startGeneration() {
        guard inputLimitState != .tooLong else {
            phase = .failure(.inputTooLong)
            return
        }
        generationTask?.cancel()
        isEditingResult = false
        phase = .generating

        let request = EnhancementRequest(rawInput: rawInput, profile: profile)
        generationTask = Task { [model] in
            if let failure = await model.availability() {
                guard !Task.isCancelled else { return }
                self.phase = .failure(failure)
                return
            }
            do {
                let result = try await model.enhance(request)
                guard !Task.isCancelled else { return }
                self.apply(result)
            } catch is CancellationError {
                // Superseded by a newer request; leave state alone.
            } catch let failure as EnhancementFailure {
                guard !Task.isCancelled else { return }
                self.phase = .failure(failure)
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failure(.generationFailed)
            }
        }
    }

    private func apply(_ result: EnhancementBundle) {
        // A provider that returns nothing usable is a failure, not a result:
        // otherwise the panel renders an empty body and Copy silently no-ops.
        guard !result.suggestions.isEmpty else {
            phase = .failure(.generationFailed)
            return
        }
        editsBeforeRegenerate = nil
        editedPrompts.removeAll()
        bundle = result
        if !result.suggestions.contains(where: { $0.style == selectedStyle }) {
            selectedStyle = result.suggestions.first?.style ?? .balanced
        }
        phase = .result
    }

    /// "Edit input" recovery: return to the editor with the text preserved so
    /// the user can shorten it (PRD §20 — never silently truncate).
    func editInput() {
        generationTask?.cancel()
        generationTask = nil
        phase = .input
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        if let restored = editsBeforeRegenerate {
            editedPrompts = restored
            editsBeforeRegenerate = nil
        }
        if bundle != nil {
            phase = .result
        } else {
            phase = .failure(.generationCancelled)
        }
    }

    // MARK: - Selection & editing

    func select(_ style: SuggestionStyle) {
        guard bundle?.suggestion(for: style) != nil else { return }
        selectedStyle = style
    }

    /// The text currently shown for the selected variant (edited or original).
    var currentPromptText: String {
        get {
            editedPrompts[selectedStyle]
                ?? bundle?.suggestion(for: selectedStyle)?.prompt
                ?? ""
        }
        set {
            editedPrompts[selectedStyle] = newValue
        }
    }

    var currentStyleWasEdited: Bool {
        guard let original = bundle?.suggestion(for: selectedStyle)?.prompt,
              let edited = editedPrompts[selectedStyle] else { return false }
        return edited != original
    }

    func beginEditing() { isEditingResult = true }
    func endEditing() { isEditingResult = false }

    // MARK: - Delivery

    /// ↵ Copy selected result and close (PRD §13).
    func copySelectedAndClose() {
        guard phase == .result, !currentPromptText.isEmpty else { return }
        clipboard.replace(with: currentPromptText)
        recordHistory()
        onToast?("Enhanced prompt copied")
        onRequestClose?()
    }

    /// ⌘⇧C Copy without closing.
    func copyWithoutClosing() {
        guard phase == .result, !currentPromptText.isEmpty else { return }
        clipboard.replace(with: currentPromptText)
        recordHistory()
        onToast?("Copied — panel stays open")
    }

    /// Writes the copied enhancement to local history, when enabled and the
    /// source app isn't excluded (PRD §15).
    private func recordHistory() {
        guard settings.historyEnabled,
              !settings.isExcluded(bundleID: sourceBundleID) else { return }
        // Copy-without-closing followed by Copy & Close is one delivery.
        let fingerprint = "\(selectedStyle.rawValue)\u{1}\(currentPromptText)"
        guard fingerprint != lastRecordedFingerprint else { return }
        lastRecordedFingerprint = fingerprint
        history.record(
            HistoryEntry(
                original: rawInput,
                enhanced: currentPromptText,
                profile: profile,
                style: selectedStyle,
                date: Date(),
                wasEdited: currentStyleWasEdited,
                wasCopied: true
            )
        )
    }

    /// Instant Enhance (PRD §6.3): no panel — read the clipboard, enhance it
    /// with the saved defaults, and write the result back, keeping the previous
    /// clipboard value so the user can restore it.
    ///
    /// Deliberately touches **no** panel state: it runs while the panel may be
    /// open on a result the user is editing, and swapping `bundle`/`rawInput`
    /// underneath that view would mismatch the shown original with the copied
    /// text. Everything here is local.
    func instantEnhance() async {
        guard instantTask == nil else { return }   // one at a time
        let task = Task { await performInstantEnhance() }
        instantTask = task
        await task.value
        instantTask = nil
    }

    private func performInstantEnhance() async {
        // The excluded-apps rule must be evaluated against the app the user is
        // in *right now*, not whichever app last opened the panel — otherwise a
        // secret copied from an excluded app gets written to history.
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !settings.isExcluded(bundleID: source) else {
            onToast?("Skipped — this app is excluded")
            return
        }
        guard let text = clipboard.readText() else {
            onToast?("Clipboard is empty")
            return
        }
        guard inputLimits.state(for: text) != .tooLong else {
            onToast?(EnhancementFailure.inputTooLong.title)
            return
        }
        if let failure = await model.availability() {
            onToast?(failure.title)
            return
        }

        do {
            let result = try await model.enhance(
                EnhancementRequest(rawInput: text, profile: settings.defaultProfile)
            )
            let chosen = result.suggestion(for: settings.defaultStyle) ?? result.suggestions.first
            guard let chosen else {
                onToast?(EnhancementFailure.generationFailed.title)
                return
            }
            clipboard.write(chosen.prompt)   // keeps a restore point
            if settings.historyEnabled {
                history.record(
                    HistoryEntry(
                        original: text, enhanced: chosen.prompt,
                        profile: settings.defaultProfile, style: chosen.style,
                        date: Date(), wasEdited: false, wasCopied: true
                    )
                )
            }
            onToast?("Prompt enhanced · restore from the menu bar")
        } catch let failure as EnhancementFailure {
            onToast?(failure.title)
        } catch {
            onToast?(EnhancementFailure.generationFailed.title)
        }
    }

    /// Puts the pre-Instant-Enhance clipboard value back.
    func restoreClipboard() {
        if clipboard.restorePrevious() {
            onToast?("Clipboard restored")
        } else {
            onToast?("Nothing to restore")
        }
    }

    var canRestoreClipboard: Bool { clipboard.hasRestorePoint }

    /// Copy the original input verbatim (recovery affordance for failures §21).
    func copyOriginal() {
        guard !rawInput.isEmpty else { return }
        clipboard.replace(with: rawInput)
        onToast?("Original copied")
    }

    func requestClose() {
        // Never dismiss mid-generation from a focus loss; explicit Esc still works.
        generationTask?.cancel()
        onRequestClose?()
    }
}
