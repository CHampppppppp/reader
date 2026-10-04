import AppKit
import Carbon

struct HotKeyPressState {
    private var isPressed = false

    mutating func update(pressed: Bool) -> Bool {
        let shouldTrigger = pressed && !isPressed
        isPressed = pressed
        return shouldTrigger
    }
}

final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var activeID: UInt32 = 0
    private var pressState = HotKeyPressState()
    var onPress: (() -> Void)?
    var isRegistered: Bool { reference != nil }

    init() {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x52454144, identifier.id == hotKey.activeID else {
                return OSStatus(eventNotHandledErr)
            }
            if hotKey.pressState.update(pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed)) {
                hotKey.onPress?()
            }
            return noErr
        }, 2, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    // Register the replacement first so a conflict never loses the working shortcut.
    func register(_ shortcut: Shortcut) -> OSStatus {
        guard handler != nil else { return OSStatus(eventNotHandledErr) }
        let nextID = activeID &+ 1
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                        EventHotKeyID(signature: 0x52454144, id: nextID),
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr else { return status }
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement
        activeID = nextID
        pressState = HotKeyPressState()
        return noErr
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
