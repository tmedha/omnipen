import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon's `RegisterEventHotKey`, deliberately not
/// `NSEvent.addGlobalMonitorForEvents`, which would require the Accessibility
/// permission.
///
/// The tradeoff is that a registered key is captured system-wide, so bare keys
/// like `P` or `Esc` may only live in the `armed` group and must be torn down
/// the moment the pen is put away.
@MainActor
final class HotKeyManager {

    struct Combo: Hashable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    enum Group: String {
        case global
        case armed
        /// Suspended while a text box has focus, so typing reaches the text view.
        case textEditing
    }

    static let shared = HotKeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var combos: [Combo: UInt32] = [:]
    private var groups: [Group: [UInt32]] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    @discardableResult
    func register(
        _ keyCode: Int,
        modifiers: UInt32 = 0,
        group: Group = .global,
        handler: @escaping () -> Void
    ) -> Bool {
        installEventHandlerIfNeeded()

        let combo = Combo(keyCode: UInt32(keyCode), modifiers: modifiers)
        // Replace rather than stack a second, unreachable binding.
        if let existing = combos[combo] { unregister(id: existing) }

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            NSLog("Omnipen: could not register hotkey \(keyCode)/\(modifiers) (OSStatus \(status))")
            return false
        }

        refs[id] = ref
        handlers[id] = handler
        combos[combo] = id
        groups[group, default: []].append(id)
        return true
    }

    func unregisterGroup(_ group: Group) {
        for id in groups[group] ?? [] { unregister(id: id) }
        groups[group] = []
    }

    private func unregister(id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        handlers[id] = nil
        combos = combos.filter { $0.value != id }
        for (group, ids) in groups {
            groups[group] = ids.filter { $0 != id }
        }
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            omnipenHotKeyCallback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private static let signature: OSType = 0x4F4D_4E50
}

/// Carbon dispatches on the main run loop, so the actor hop is an assertion
/// rather than a thread change.
private func omnipenHotKeyCallback(
    _ callRef: EventHandlerCallRef?,
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

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { manager.fire(id: hotKeyID.id) }
    return noErr
}

enum Mod {
    static let command = UInt32(cmdKey)
    static let option = UInt32(optionKey)
    static let shift = UInt32(shiftKey)
    static let control = UInt32(controlKey)
}
