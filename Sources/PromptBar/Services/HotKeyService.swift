import AppKit
import Carbon.HIToolbox

/// Four-char code identifying hotkeys registered by this app ('PRBT').
private let promptBarHotKeySignature = OSType(0x5052_4254)

/// A configurable global shortcut (PRD §13). Modifier flags use Carbon values.
struct HotKey: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// Default "Open PromptBar": ⇧⌥Space.
    static let openPanel = HotKey(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(shiftKey | optionKey)
    )

    /// Default "Instant Enhance": ⌃⌥P.
    static let instantEnhance = HotKey(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(controlKey | optionKey)
    )
}

/// Registers and dispatches global hotkeys via Carbon's `RegisterEventHotKey`.
/// Dependency-free and does not require Accessibility permission (PRD §13).
@MainActor
final class HotKeyService {
    private struct Registration {
        var ref: EventHotKeyRef?
        var handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    fileprivate static let signature = promptBarHotKeySignature

    init() {
        installHandlerIfNeeded()
    }

    /// Register a hotkey; returns an opaque id that can be used to unregister.
    @discardableResult
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr else {
            NSLog("PromptBar: failed to register hotkey (status \(status))")
            return nil
        }
        registrations[id] = Registration(ref: ref, handler: handler)
        return id
    }

    func unregister(_ id: UInt32) {
        guard let reg = registrations.removeValue(forKey: id) else { return }
        if let ref = reg.ref { UnregisterEventHotKey(ref) }
    }

    fileprivate func fire(id: UInt32) {
        registrations[id]?.handler()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventCallback,
            1,
            &spec,
            selfPtr,
            &eventHandler
        )
    }
}

/// C callback trampoline. Runs on the main thread during event dispatch.
private func hotKeyEventCallback(
    _ handlerCallRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    // Other in-process registrants share this dispatcher target, so ignore
    // anything that is not ours before dispatching on the id.
    guard hotKeyID.signature == promptBarHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        service.fire(id: hotKeyID.id)
    }
    return noErr
}
