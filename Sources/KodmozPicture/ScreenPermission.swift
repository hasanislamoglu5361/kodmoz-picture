import AppKit
import CoreGraphics

/// Ekran kaydı izni (TCC) yönetimi.
///
/// macOS, TCC kararını süreç başlarken okur ve süreç yeniden başlatılmadıkça
/// güncellemez. Bu yüzden kullanıcı izni Sistem Ayarları'nda işaretlediğinde
/// çalışan süreç hâlâ "izin yok" görür; her yakalamada aynı uyarının çıkmasının
/// nedeni budur. Çözüm: izin verildiğini tespit ettiğimiz anda uygulamayı
/// yeniden başlatmak. İzni kullanıcı adına biz de veremeyiz; yalnızca
/// sistemin kendi penceresini tetikleyebiliriz.
enum ScreenPermission {

    private static let privacyURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private enum K {
        static let lastRelaunch = "screenPermissionLastRelaunch"
        static let relaunchCount = "screenPermissionRelaunchCount"
    }

    private static var alertedThisRun = false
    private static var watcher: Timer?

    /// Aynı izin sorunu için üst üste en fazla bu kadar yeniden başlatma
    /// yapılır. Yeniden başlatmaya rağmen izin görünmüyorsa TCC kaydı bu
    /// uygulama kimliğiyle eşleşmiyor demektir; döngüye girmek yerine
    /// kullanıcıya yol gösterilir.
    private static let maxRelaunchAttempts = 2
    private static let attemptWindow: TimeInterval = 180

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Sistemin izin penceresini gösterir (uygulamayı TCC listesine ekler).
    /// İzin daha önce verildiyse pencere çıkmaz ve `true` döner.
    @discardableResult
    static func request() -> Bool {
        if isGranted { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        NSWorkspace.shared.open(privacyURL)
        watchForGrant()
    }

    /// Açılışta çağrılır: izin yoksa sistem penceresini tetikler ve izni
    /// izlemeye başlar. Kullanıcıyı kendi uyarımızla karşılamıyoruz; uyarı
    /// yalnızca bir yakalama gerçekten başarısız olduğunda çıkar.
    static func ensureAtLaunch() {
        if isGranted {
            // İzin yolunda: önceki yeniden başlatma sayacını sıfırla ki
            // ileride izin kaldırılıp yeniden verilirse akış çalışsın.
            let d = UserDefaults.standard
            d.removeObject(forKey: K.lastRelaunch)
            d.removeObject(forKey: K.relaunchCount)
            return
        }
        watchForGrant()
        // Sistem penceresi kurulum başına bir kez anlamlı; kullanıcı daha
        // önce reddettiyse pencere çıkmaz ve `false` döner.
        if request() { relaunchIfAllowed() }
    }

    /// Yakalama izin yüzünden başarısız olduğunda çağrılır.
    /// Sistem penceresini yeniden tetiklemeyiz — her basışta üst üste soru
    /// çıkmasının nedeni buydu. İzni izleriz ve çalışma başına bir kez
    /// yönlendirme uyarısı gösteririz.
    /// - Returns: Kullanıcıya uyarı gösterilmesi gerekiyorsa `true`.
    static func handleCaptureFailure() -> Bool {
        watchForGrant()
        return true
    }

    /// Kullanıcı Sistem Ayarları'nda anahtarı açtığında ek bir tuşa basmasına
    /// gerek kalmasın diye izni sınırlı süre izler. Süre dolunca kendini
    /// kapatır; arka planda sonsuz yoklama yapılmaz.
    static func watchForGrant(timeout: TimeInterval = 300) {
        guard watcher == nil, !isGranted else { return }
        let deadline = Date().addingTimeInterval(timeout)
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            if isGranted {
                stopWatching()
                relaunchIfAllowed()
            } else if Date() > deadline {
                stopWatching()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watcher = timer
    }

    private static func stopWatching() {
        watcher?.invalidate()
        watcher = nil
    }

    /// TCC'deki ekran kaydı kararını siler.
    ///
    /// İmza değiştiğinde (ad-hoc → Apple Development) eski karar eski kimliğe
    /// bağlı kalır: Sistem Ayarları'nda anahtar açık görünür ama uygulama izni
    /// göremez ve her seferinde yeniden ister. Sıfırlama, izin listesini temiz
    /// bir kayıtla yeniden oluşturur.
    static func resetDecision() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "ScreenCapture",
                       Bundle.main.bundleIdentifier ?? "com.kodmoz.picture"]
        p.standardError = Pipe()
        p.standardOutput = Pipe()
        do { try p.run(); p.waitUntilExit() } catch {
            NSLog("KodmozPicture: tccutil çalıştırılamadı — \(error)")
        }
    }

    /// Kararı sıfırlayıp yeniden başlatır; yeni süreç temiz kayıtla sistemin
    /// izin penceresini yeniden gösterir.
    static func resetAndRelaunch() {
        resetDecision()
        let d = UserDefaults.standard
        d.removeObject(forKey: K.lastRelaunch)
        d.removeObject(forKey: K.relaunchCount)
        relaunch()
    }

    /// İzin verilmişse uygulamayı yeniden başlatır.
    /// - Returns: Yeniden başlatma başlatıldıysa `true`.
    @discardableResult
    static func relaunchIfAllowed() -> Bool {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let last = d.double(forKey: K.lastRelaunch)
        let fresh = now - last < attemptWindow
        let attempts = fresh ? d.integer(forKey: K.relaunchCount) + 1 : 1

        guard attempts <= maxRelaunchAttempts else { return false }

        d.set(now, forKey: K.lastRelaunch)
        d.set(attempts, forKey: K.relaunchCount)
        relaunch()
        return true
    }

    /// Eski süreç tamamen kapanmadan yeni örnek açılmaz; böylece kısayolu
    /// iki örnek aynı anda kapmaya çalışmaz.
    static func relaunch() {
        stopWatching()
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; "
            + "sleep 0.8; /usr/bin/open -n \(quoted)"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// Çalışma başına en fazla bir kez gösterilir; her başarısız yakalamada
    /// aynı pencereyi açıp kullanıcıyı döngüye sokmuyoruz.
    static func presentAlert(force: Bool = false) {
        guard NSApp.isRunning, Bundle.main.bundleIdentifier != nil else { return }
        guard force || !alertedThisRun else { return }
        alertedThisRun = true

        // Menü çubuğu uygulaması arka planda çalışır; pencereyi öne almazsak
        // uyarı görünmez kalır ve kullanıcı yanıtlayamaz.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Ekran Kaydı izni gerekiyor"
        alert.informativeText = """
        Sistem Ayarları → Gizlilik ve Güvenlik → Ekran Kaydı bölümünde \
        Kodmoz Picture'ı işaretleyin. İzin verdiğinizde uygulama kendini \
        otomatik yeniden başlatır; sonrasında kısayol çalışır.

        Anahtar açık göründüğü hâlde uygulama hâlâ izin istiyorsa eski bir \
        izin kaydı kalmış demektir. "İzni Sıfırla" kaydı temizleyip sistemin \
        izin penceresini yeniden gösterir.
        """
        alert.addButton(withTitle: "Ayarları Aç")
        alert.addButton(withTitle: "İzin Verdim, Yeniden Başlat")
        alert.addButton(withTitle: "İzni Sıfırla")
        alert.addButton(withTitle: "Kapat")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSettings()
        case .alertSecondButtonReturn:
            relaunch()
        case .alertThirdButtonReturn:
            resetAndRelaunch()
        default:
            break
        }
    }
}
