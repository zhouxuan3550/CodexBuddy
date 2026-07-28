import Carbon.HIToolbox
import Foundation

/// Registers a system-wide hotkey via Carbon's RegisterEventHotKey, which
/// works without Accessibility permission (unlike CGEventTap/NSEvent global
/// monitors). Deallocating the instance unregisters the key.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    /// Default binding: ⌥⌘U toggles the usage dashboard.
    static func optionCommandU(handler: @escaping () -> Void) -> GlobalHotKey {
        GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_U),
            modifiers: UInt32(cmdKey | optionKey),
            handler: handler
        )
    }

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        // The dispatcher target receives hotkeys even while another app is
        // active; the application target would only see them in-app.
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in hotKey.handler() }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4342_4459) /* "CBDY" */, id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
