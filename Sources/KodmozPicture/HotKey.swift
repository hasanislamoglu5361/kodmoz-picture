import AppKit
import Carbon.HIToolbox
import Foundation

/// Karbon tabanlı GLOBAL kısayol. Erişilebilirlik izni GEREKTİRMEZ
/// (NSEvent.addGlobalMonitorForEvents'ın aksine).
final class HotKey {
    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var hotKeyRef: EventHotKeyRef?
    private let handlerID: UInt32
    private let callback: () -> Void

    /// Karbon değiştirici maskesi
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    init?(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        guard modifiers != 0 else { return nil }
        self.callback = callback
        self.handlerID = HotKey.nextID
        HotKey.nextID += 1
        HotKey.registry[handlerID] = self
        HotKey.installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B505443), id: handlerID) // 'KPTC'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let r = ref else {
            HotKey.registry.removeValue(forKey: handlerID)
            return nil
        }
        self.hotKeyRef = r
    }

    deinit { unregister() }

    func unregister() {
        if let r = hotKeyRef {
            UnregisterEventHotKey(r)
            hotKeyRef = nil
        }
        HotKey.registry.removeValue(forKey: handlerID)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr else { return OSStatus(eventNotHandledErr) }
            if let hk = HotKey.registry[hkID.id] {
                DispatchQueue.main.async { hk.callback() }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &spec, nil, nil)
    }
}
