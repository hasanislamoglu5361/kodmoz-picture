import AppKit
import Carbon.HIToolbox
import Foundation

/// Bir global kısayolun tuş kodu + değiştirici maskesi.
struct HotKeySpec {
    var code: UInt32
    var modifiers: UInt32

    var description: String { Preferences.describe(code: code, modifiers: modifiers) }
}

/// Tercihler — UserDefaults üzerinde ince bir sarmalayıcı.
final class Preferences {
    static let shared = Preferences()
    static let changed = Notification.Name("KodmozPicturePreferencesChanged")

    private let d = UserDefaults.standard

    private enum K {
        static let folder = "saveFolder"
        static let copyClipboard = "copyToClipboard"
        static let historyCount = "historyCount"
        static let selectionCode = "selectionHotKeyCode"
        static let selectionMods = "selectionHotKeyModifiers"
        static let fullCode = "fullHotKeyCode"
        static let fullMods = "fullHotKeyModifiers"
        static let showNotification = "showNotification"
        static let playSound = "playSound"
    }

    private init() {
        let cmdShift = HotKey.carbonModifiers([.command, .shift])
        d.register(defaults: [
            K.copyClipboard: true,
            K.historyCount: 12,
            K.selectionCode: Int(kVK_ANSI_1),
            K.selectionMods: cmdShift,
            K.fullCode: Int(kVK_ANSI_2),
            K.fullMods: cmdShift,
            K.showNotification: true,
            K.playSound: true,
        ])
    }

    var saveFolder: URL {
        get {
            if let s = d.string(forKey: K.folder), !s.isEmpty {
                return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
            }
            let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
            return pics.appendingPathComponent("KodmozPicture", isDirectory: true)
        }
        set {
            d.set(newValue.path, forKey: K.folder)
            announce()
        }
    }

    var copyToClipboard: Bool {
        get { d.bool(forKey: K.copyClipboard) }
        set { d.set(newValue, forKey: K.copyClipboard); announce() }
    }

    var showNotification: Bool {
        get { d.bool(forKey: K.showNotification) }
        set { d.set(newValue, forKey: K.showNotification); announce() }
    }

    var playSound: Bool {
        get { d.bool(forKey: K.playSound) }
        set { d.set(newValue, forKey: K.playSound); announce() }
    }

    var historyCount: Int {
        get { max(1, min(50, d.integer(forKey: K.historyCount))) }
        set { d.set(max(1, min(50, newValue)), forKey: K.historyCount); announce() }
    }

    /// Alan seçerek yakalama — ⌘⇧1
    var selectionHotKey: HotKeySpec {
        get {
            HotKeySpec(code: UInt32(d.integer(forKey: K.selectionCode)),
                       modifiers: UInt32(d.integer(forKey: K.selectionMods)))
        }
        set {
            d.set(Int(newValue.code), forKey: K.selectionCode)
            d.set(Int(newValue.modifiers), forKey: K.selectionMods)
            announce()
        }
    }

    /// Tüm ekranı yakalama — ⌘⇧2
    var fullHotKey: HotKeySpec {
        get {
            HotKeySpec(code: UInt32(d.integer(forKey: K.fullCode)),
                       modifiers: UInt32(d.integer(forKey: K.fullMods)))
        }
        set {
            d.set(Int(newValue.code), forKey: K.fullCode)
            d.set(Int(newValue.modifiers), forKey: K.fullMods)
            announce()
        }
    }

    private func announce() {
        NotificationCenter.default.post(name: Preferences.changed, object: nil)
    }

    /// İnsan okur biçim: "⌘⇧1"
    static func describe(code: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        s += keyName(code)
        return s.isEmpty ? "—" : s
    }

    static func keyName(_ code: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Comma: ",",
            kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";",
            kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_Grave: "`",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12",
        ]
        return map[Int(code)] ?? "?"
    }
}
