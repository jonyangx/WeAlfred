import Carbon

@MainActor
final class HotKey {
    private let action: () -> Void
    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?
    private static let signature: UInt32 = 0x57414C46 // WALF

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() -> String? {
        let target = GetApplicationEventTarget()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var received = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &received
            )
            return MainActor.assumeIsolated {
                guard status == noErr, received.signature == HotKey.signature, received.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action()
                return noErr
            }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return nil }

        let options = [(optionKey, "⌥ 空格"), (controlKey | optionKey, "⌃⌥ 空格")]
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        for (modifiers, label) in options {
            let result = RegisterEventHotKey(
                UInt32(kVK_Space), UInt32(modifiers), identifier, target,
                OptionBits(kEventHotKeyExclusive), &registration
            )
            if result == noErr { return label }
        }

        unregister()
        return nil
    }

    func unregister() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
    }
}
