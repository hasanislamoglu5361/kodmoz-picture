import AppKit
import Carbon.HIToolbox
import CoreGraphics

// CLI yardımcıları (bundle içinden de çağrılabilir):
//   KodmozPicture --capture [full|selection|window]   → tek seferlik ekran görüntüsü
//   KodmozPicture --make-icon <dizin>                 → ikon PNG'lerini üretir
//   KodmozPicture --diagnose [dosya]                  → izin/kısayol durum raporu
let args = CommandLine.arguments

if args.count > 1, args[1] == "--diagnose" {
    _ = NSApplication.shared   // Karbon olay hedefi için gerekli

    func probeCapture() -> String {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kodmoz-diagnose-\(UUID().uuidString).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-t", "png", tmp.path]
        let errPipe = Pipe()
        p.standardError = errPipe
        do { try p.run(); p.waitUntilExit() } catch { return "çalıştırılamadı: \(error)" }
        let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        let stderr = (String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try? FileManager.default.removeItem(at: tmp)
        return size > 0 ? "BAŞARILI (\(size) bayt)" : "BAŞARISIZ (stderr: \(stderr))"
    }

    var lines: [String] = []
    lines.append("yol: \(Bundle.main.bundlePath)")
    lines.append("bundleID: \(Bundle.main.bundleIdentifier ?? "yok")")
    lines.append("sürüm: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
    lines.append("ekran kaydı preflight: \(CGPreflightScreenCaptureAccess())")
    lines.append("screencapture denemesi: \(probeCapture())")
    let code = Preferences.shared.hotKeyCode
    let mods = Preferences.shared.hotKeyModifiers
    lines.append("kayıtlı kısayol: \(Preferences.describe(code: code, modifiers: mods)) "
                 + "(keyCode=\(code) mods=\(mods))")
    var ref: EventHotKeyRef?
    let probeID = EventHotKeyID(signature: OSType(0x44494147), id: 1) // 'DIAG'
    let st = RegisterEventHotKey(code, mods, probeID, GetApplicationEventTarget(), 0, &ref)
    if st == noErr {
        lines.append("kısayol kaydı: BOŞ (bu süreç kaydedebildi)")
        if let r = ref { UnregisterEventHotKey(r) }
    } else if st == OSStatus(-9878) {
        lines.append("kısayol kaydı: DOLU (başka süreç tutuyor)")
    } else {
        lines.append("kısayol kaydı: HATA \(st)")
    }
    if let bid = Bundle.main.bundleIdentifier {
        let n = NSRunningApplication.runningApplications(withBundleIdentifier: bid).count
        lines.append("çalışan örnek sayısı: \(n)")
    }
    let report = lines.joined(separator: "\n") + "\n"
    if args.count > 2 {
        try? report.write(toFile: args[2], atomically: true, encoding: .utf8)
    } else {
        print(report, terminator: "")
    }
    exit(0)
}

if args.count > 1, args[1] == "--make-icon" {
    let dir = args.count > 2 ? args[2] : FileManager.default.currentDirectoryPath
    IconGen.makeIconSet(into: dir)
    exit(0)
}

if args.count > 1, args[1] == "--capture" {
    let mode = CaptureMode(rawValue: args.count > 2 ? args[2] : "full") ?? .full
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if let result = CaptureEngine.shared.capture(mode: mode) {
        print(result.url.path)
        exit(0)
    }
    FileHandle.standardError.write(Data("FAIL: ekran görüntüsü alınamadı\n".utf8))
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // sadece menü çubuğu, Dock'ta görünmez
app.run()
