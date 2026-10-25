import AppKit
import Foundation

enum CaptureMode: String, CaseIterable {
    case full          // tüm ekranlar
    case mainScreen    // ana ekran
    case selection     // fareyle alan seç
    case window        // pencere seç

    var title: String {
        switch self {
        case .full: return "Tüm ekranlar"
        case .mainScreen: return "Ana ekran"
        case .selection: return "Alan seç (fareyle)"
        case .window: return "Pencere seç"
        }
    }

    var shortTitle: String {
        switch self {
        case .full: return "tam ekran"
        case .mainScreen: return "ana ekran"
        case .selection: return "alan seçimi"
        case .window: return "pencere"
        }
    }
}

struct CaptureResult {
    let url: URL
    let image: NSImage
    let mode: CaptureMode
    let createdAt: Date
}

final class CaptureEngine {
    static let shared = CaptureEngine()

    private let fm = FileManager.default

    /// Ekran görüntüsü alır, diske yazar, panoya kopyalar.
    @discardableResult
    func capture(mode: CaptureMode) -> CaptureResult? {
        let folder = Preferences.shared.saveFolder
        guard ensureFolder(folder) else {
            NSSound.beep()
            return nil
        }
        let url = folder.appendingPathComponent(Self.fileName())
        guard runScreencapture(mode: mode, to: url), fm.fileExists(atPath: url.path) else {
            NSSound.beep()
            return nil
        }
        guard let image = NSImage(contentsOf: url) else { return nil }

        if Preferences.shared.copyToClipboard {
            copyToPasteboard(image: image, url: url)
        }
        if Preferences.shared.playSound {
            NSSound(named: "Grab")?.play()
        }
        return CaptureResult(url: url, image: image, mode: mode, createdAt: Date())
    }

    // MARK: - Parçalar

    private func ensureFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            NSLog("KodmozPicture: klasör oluşturulamadı \(url.path) — \(error)")
            return false
        }
    }

    private func runScreencapture(mode: CaptureMode, to url: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var args = ["-x", "-t", "png"]
        switch mode {
        case .full: args.append("-m")            // ana ekran (çoklu monitörde tek dosya)
        case .mainScreen: break
        case .selection: args.append("-i")       // etkileşimli alan seçimi
        case .window: args.append("-w")          // pencere seçimi
        }
        args.append(url.path)
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            NSLog("KodmozPicture: screencapture çalıştırılamadı — \(error)")
            return false
        }
        if p.terminationStatus != 0 {
            // Kullanıcı ESC ile iptal ettiyse dosya oluşmaz; hata saymıyoruz.
            return p.terminationStatus == 0 || fm.fileExists(atPath: url.path)
        }
        return true
    }

    private func copyToPasteboard(image: NSImage, url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        // Görüntü + dosya referansı: Finder/WhatsApp/Slack dosyayı tanır.
        pb.writeObjects([image, url as NSURL])
    }

    static func fileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Kodmoz \(f.string(from: date)).png"
    }

    /// Kayıtlı görüntüler — en yeniden eskiye.
    func history(limit: Int = 12) -> [URL] {
        let folder = Preferences.shared.saveFolder
        guard let files = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
            .prefix(limit)
            .map { $0 }
    }
}
