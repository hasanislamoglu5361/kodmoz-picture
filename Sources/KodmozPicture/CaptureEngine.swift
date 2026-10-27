import AppKit
import CoreGraphics
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

    /// Kullanıcı ESC ile iptal edebilir; iptal, hata gibi raporlanmamalı.
    var isInteractive: Bool { self == .selection || self == .window }
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

    private enum ScreencaptureOutcome {
        case success
        case cancelled
        case failed
    }

    /// screencapture `-x` ile sessiz çalıştığı için sesi biz çalıyoruz.
    /// "Grab" macOS'ta yok; sistemin kendi ekran görüntüsü sesini kullan.
    private static let captureSound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport"
            + "/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Glass")
    }()

    /// Ekran görüntüsü alır, diske yazar, panoya kopyalar.
    @discardableResult
    func capture(mode: CaptureMode) -> CaptureResult? {
        let folder = Preferences.shared.saveFolder
        guard ensureFolder(folder) else {
            NSSound.beep()
            return nil
        }
        let url = uniqueURL(in: folder)
        switch runScreencapture(mode: mode, to: url) {
        case .success:
            break
        case .cancelled:
            // Kullanıcı ESC ile vazgeçti: ses/bip yok, dosya da yok.
            try? fm.removeItem(at: url)
            return nil
        case .failed:
            try? fm.removeItem(at: url)
            if !ScreenPermission.isGranted {
                if ScreenPermission.handleCaptureFailure() {
                    ScreenPermission.presentAlert()
                }
            } else {
                NSSound.beep()
            }
            return nil
        }
        guard let image = NSImage(contentsOf: url) else {
            NSLog("KodmozPicture: görüntü okunamadı \(url.path)")
            NSSound.beep()
            return nil
        }

        if Preferences.shared.copyToClipboard {
            copyToPasteboard(image: image, url: url)
        }
        if Preferences.shared.playSound {
            Self.captureSound?.play()
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

    private func runScreencapture(mode: CaptureMode, to url: URL) -> ScreencaptureOutcome {
        try? fm.removeItem(at: url)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var args = ["-x", "-t", "png"]
        switch mode {
        case .full: break                        // tüm ekranlar (varsayılan)
        case .mainScreen: args.append("-m")      // yalnızca ana ekran
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
            return .failed
        }

        if hasImage(at: url) { return .success }
        // Etkileşimli modlarda dosya yoksa kullanıcı iptal etmiştir.
        if mode.isInteractive { return .cancelled }
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        if !stderr.isEmpty {
            NSLog("KodmozPicture: screencapture hatası — \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return .failed
    }

    private func hasImage(at url: URL) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return false }
        return size.intValue > 0
    }

    private func copyToPasteboard(image: NSImage, url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        // Görüntü + dosya referansı: Finder/WhatsApp/Slack dosyayı tanır.
        // Dosya gerçekten duruyorsa referansı yaz; aksi hâlde hedef uygulama
        // "dosya bulunamadı" der. Bu durumda yalnızca görüntüyü bırakırız.
        if fm.fileExists(atPath: url.path) {
            pb.writeObjects([image, url as NSURL])
        } else {
            NSLog("KodmozPicture: dosya referansı yazılmadı, dosya yok — \(url.path)")
            pb.writeObjects([image])
        }
    }

    static func fileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Kodmoz \(f.string(from: date)).png"
    }

    /// Aynı saniyedeki ikinci yakalama önceki dosyayı ezmesin.
    private func uniqueURL(in folder: URL) -> URL {
        let base = Self.fileName()
        let stem = (base as NSString).deletingPathExtension
        var url = folder.appendingPathComponent(base)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem)-\(n).png")
            n += 1
        }
        return url
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
