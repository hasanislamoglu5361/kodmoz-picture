import AppKit

// CLI yardımcıları (bundle içinden de çağrılabilir):
//   KodmozPicture --capture [full|selection|window]   → tek seferlik ekran görüntüsü
//   KodmozPicture --make-icon <dizin>                 → ikon PNG'lerini üretir
let args = CommandLine.arguments

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
