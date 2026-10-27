import AppKit
import Foundation
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate,
                         UNUserNotificationCenterDelegate {

    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var prefsWindow: PreferencesWindowController?
    private var lastCapture: CaptureResult?

    // MARK: - Yaşam döngüsü

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = LogoRenderer.statusImage(size: 18)
            button.image?.isTemplate = true
            button.toolTip = "Kodmoz Picture — ekran görüntüsü"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        buildMenu(menu)

        registerHotKey()
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                              name: Preferences.changed, object: nil)
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        ensureFolderExists()

        // macOS izni süreç başlarken okur; izin verildiği hâlde eski süreç
        // bunu göremez. Bu yüzden açılışta izni kesinleştirip gerekirse
        // uygulamayı bir kez yeniden başlatıyoruz.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            ScreenPermission.ensureAtLaunch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
    }

    // MARK: - Kısayol

    private func registerHotKey() {
        hotKey?.unregister()
        let code = Preferences.shared.hotKeyCode
        let mods = Preferences.shared.hotKeyModifiers
        hotKey = HotKey(keyCode: code, modifiers: mods) { [weak self] in
            NSLog("KodmozPicture: kısayol tetiklendi")
            self?.captureWithFeedback()
        }
        let desc = Preferences.describe(code: code, modifiers: mods)
        if hotKey == nil {
            NSLog("KodmozPicture: kısayol kaydedilemedi — \(desc)")
            if let m = statusItem.menu {
                // Kısayolun neden çalışmadığını menüde görünür kıl.
                let uyari = NSMenuItem(title: "⚠︎ \(desc) kullanılamıyor (başka uygulama tutuyor)",
                                       action: #selector(openSettings), keyEquivalent: "")
                uyari.target = self
                m.insertItem(uyari, at: 0)
                m.insertItem(.separator(), at: 1)
            }
        } else {
            NSLog("KodmozPicture: kısayol kaydedildi — \(desc)")
        }
        statusItem.button?.toolTip = "Kodmoz Picture — \(desc)"
    }

    @objc private func prefsChanged() {
        registerHotKey()
        if let m = statusItem.menu { buildMenu(m) }
    }

    // MARK: - Menü

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let hk = Preferences.describe(code: Preferences.shared.hotKeyCode,
                                      modifiers: Preferences.shared.hotKeyModifiers)

        let capture = NSMenuItem(title: "Ekran Görüntüsü Al",
                                 action: #selector(captureNow), keyEquivalent: "")
        capture.target = self
        capture.toolTip = hk
        menu.addItem(capture)

        let alt = NSMenuItem(title: "Alan Seçerek Al",
                             action: #selector(captureSelection), keyEquivalent: "")
        alt.target = self
        menu.addItem(alt)

        let win = NSMenuItem(title: "Pencere Seçerek Al",
                             action: #selector(captureWindow), keyEquivalent: "")
        win.target = self
        menu.addItem(win)

        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "Son Görüntüler", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.delegate = self
        historyItem.submenu = sub
        menu.addItem(historyItem)

        let openFolder = NSMenuItem(title: "Klasörü Aç",
                                    action: #selector(openFolder), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Ayarlar…",
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let gh = NSMenuItem(title: "GitHub Deposu",
                            action: #selector(openRepo), keyEquivalent: "")
        gh.target = self
        menu.addItem(gh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Çıkış", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let sub = menu.items.first(where: { $0.title == "Son Görüntüler" })?.submenu,
              menu == sub else { return }
        sub.removeAllItems()
        let items = CaptureEngine.shared.history(limit: Preferences.shared.historyCount)
        if items.isEmpty {
            let bos = NSMenuItem(title: "Henüz görüntü yok", action: nil, keyEquivalent: "")
            bos.isEnabled = false
            sub.addItem(bos)
            return
        }
        for url in items {
            let title = url.deletingPathExtension().lastPathComponent
            let item = NSMenuItem(title: title, action: #selector(openHistory(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = thumbnail(for: url, height: 22)
            item.submenu = historyActions(for: url)
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let clear = NSMenuItem(title: "Listeyi Yenile", action: #selector(noop), keyEquivalent: "")
        clear.target = self
        sub.addItem(clear)
    }

    private func historyActions(for url: URL) -> NSMenu {
        let m = NSMenu()
        let open = NSMenuItem(title: "Önizleme'de Aç", action: #selector(openHistory(_:)),
                              keyEquivalent: "")
        open.target = self
        open.representedObject = url
        m.addItem(open)

        let copy = NSMenuItem(title: "Panoya Kopyala", action: #selector(copyHistory(_:)),
                              keyEquivalent: "")
        copy.target = self
        copy.representedObject = url
        m.addItem(copy)

        let reveal = NSMenuItem(title: "Finder'da Göster", action: #selector(revealHistory(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = url
        m.addItem(reveal)

        m.addItem(.separator())
        let trash = NSMenuItem(title: "Çöp Kutusuna Taşı", action: #selector(trashHistory(_:)),
                               keyEquivalent: "")
        trash.target = self
        trash.representedObject = url
        m.addItem(trash)
        return m
    }

    private func thumbnail(for url: URL, height: CGFloat) -> NSImage? {
        guard let img = NSImage(contentsOf: url), img.size.height > 0 else { return nil }
        let scale = height / img.size.height
        let size = NSSize(width: max(1, img.size.width * scale), height: height)
        let out = NSImage(size: size)
        out.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: size))
        out.unlockFocus()
        return out
    }

    // MARK: - Eylemler

    @objc private func captureNow() { captureWithFeedback(mode: Preferences.shared.mode) }
    @objc private func captureSelection() { captureWithFeedback(mode: .selection) }
    @objc private func captureWindow() { captureWithFeedback(mode: .window) }

    private func captureWithFeedback(mode: CaptureMode? = nil) {
        // Menü açıkken ekran görüntüsü alınacağı için önce menüyü kapat.
        statusItem.menu?.cancelTracking()
        let m = mode ?? Preferences.shared.mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self = self else { return }
            if let result = CaptureEngine.shared.capture(mode: m) {
                self.lastCapture = result
                self.notify(result)
                self.rebuildHistoryMenu()
            }
        }
    }

    private func rebuildHistoryMenu() {
        guard let menu = statusItem.menu,
              let sub = menu.items.first(where: { $0.title == "Son Görüntüler" })?.submenu
        else { return }
        menuNeedsUpdate(sub)
    }

    @objc private func openHistory(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyHistory(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let img = NSImage(contentsOf: url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }

    @objc private func revealHistory(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func trashHistory(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        rebuildHistoryMenu()
    }

    @objc private func noop() {}

    @objc private func openFolder() {
        let folder = Preferences.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func openSettings() {
        if prefsWindow == nil { prefsWindow = PreferencesWindowController() }
        prefsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openRepo() {
        if let url = URL(string: "https://github.com/hasanislamoglu5361/kodmoz-picture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func ensureFolderExists() {
        try? FileManager.default.createDirectory(at: Preferences.shared.saveFolder,
                                                withIntermediateDirectories: true)
    }

    // MARK: - Bildirim

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ result: CaptureResult) {
        guard Preferences.shared.showNotification else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ekran görüntüsü alındı"
        content.body = "\(result.mode.shortTitle) · panoya kopyalandı\n\(result.url.lastPathComponent)"
        content.sound = nil
        // UNNotificationAttachment dosyayı KOPYALAMAZ, kendi deposuna TAŞIR.
        // Doğrudan kayda eklersek kullanıcının dosyası klasörden kaybolur ve
        // panodaki referans kırılır. Bu yüzden eke geçici bir kopya veriyoruz;
        // sistem o kopyayı taşır, asıl dosya yerinde kalır.
        if let attach = makeTemporaryAttachment(from: result.url) {
            content.attachments = [attach]
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func makeTemporaryAttachment(from url: URL) -> UNNotificationAttachment? {
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kodmoz-bildirim-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: url, to: tmp)
        } catch {
            NSLog("KodmozPicture: bildirim eki kopyalanamadı — \(error)")
            return nil
        }
        return try? UNNotificationAttachment(identifier: "shot", url: tmp, options: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
