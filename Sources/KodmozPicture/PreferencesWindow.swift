import AppKit
import ServiceManagement

/// Kısayol kaydedici kutu: tıkla → "tuşlara bas" → kombinasyonu yakalar.
final class HotKeyRecorderView: NSView {
    var onChange: ((UInt32, UInt32) -> Void)?
    private var recording = false { didSet { updateTitle() } }
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateTitle()
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let mods = HotKey.carbonModifiers(event.modifierFlags)
        if event.keyCode == 53 {                     // ESC → iptal
            recording = false
            return
        }
        guard mods != 0 else { NSSound.beep(); return }
        recording = false
        Preferences.shared.hotKeyCode = UInt32(event.keyCode)
        Preferences.shared.hotKeyModifiers = mods
        onChange?(UInt32(event.keyCode), mods)
    }

    private func updateTitle() {
        if recording {
            label.stringValue = "Tuşlara bas… (ESC iptal)"
            label.textColor = .systemOrange
        } else {
            label.stringValue = Preferences.describe(code: Preferences.shared.hotKeyCode,
                                                     modifiers: Preferences.shared.hotKeyModifiers)
            label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
            label.textColor = .labelColor
        }
    }

    private func refreshColors() {
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 30) }
}

final class PreferencesWindowController: NSWindowController {

    private var folderLabel = NSTextField(labelWithString: "")
    private var loginCheckbox = NSButton(checkboxWithTitle: "Girişte otomatik başlat",
                                         target: nil, action: nil)

    convenience init() {
        // İçerik yüksekliği ~514 pt; pencere daha kısa olursa alt kısım kesilir.
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Kodmoz Picture — Ayarlar"
        self.init(window: win)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])

        func baslik(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: 12, weight: .semibold)
            l.textColor = .secondaryLabelColor
            return l
        }

        // 1) Kısayol
        stack.addArrangedSubview(baslik("GLOBAL KISAYOL"))
        let recorder = HotKeyRecorderView()
        recorder.onChange = { code, mods in
            Preferences.shared.hotKeyCode = code
            Preferences.shared.hotKeyModifiers = mods
        }
        stack.addArrangedSubview(recorder)

        // 2) Kayıt klasörü
        stack.addArrangedSubview(baslik("KAYIT KLASÖRÜ"))
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        folderLabel.stringValue = Preferences.shared.saveFolder.path
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.font = .systemFont(ofSize: 11)
        folderLabel.textColor = .secondaryLabelColor
        let choose = NSButton(title: "Değiştir…", target: self, action: #selector(chooseFolder))
        let openBtn = NSButton(title: "Aç", target: self, action: #selector(openFolder))
        row.addArrangedSubview(folderLabel)
        row.addArrangedSubview(choose)
        row.addArrangedSubview(openBtn)
        folderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 250).isActive = true
        stack.addArrangedSubview(row)

        // 3) Yakalama modu
        stack.addArrangedSubview(baslik("KISAYOLUN YAKALAMA MODU"))
        let modePopup = NSPopUpButton()
        for m in CaptureMode.allCases { modePopup.addItem(withTitle: m.title) }
        modePopup.selectItem(at: CaptureMode.allCases.firstIndex(of: Preferences.shared.mode) ?? 0)
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))
        stack.addArrangedSubview(modePopup)

        // 4) Davranış
        stack.addArrangedSubview(baslik("DAVRANIŞ"))
        let clip = NSButton(checkboxWithTitle: "Panoya otomatik kopyala",
                            target: self, action: #selector(toggleClipboard(_:)))
        clip.state = Preferences.shared.copyToClipboard ? .on : .off
        stack.addArrangedSubview(clip)

        let note = NSButton(checkboxWithTitle: "Bildirim göster (küçük önizlemeyle)",
                            target: self, action: #selector(toggleNotification(_:)))
        note.state = Preferences.shared.showNotification ? .on : .off
        stack.addArrangedSubview(note)

        let sound = NSButton(checkboxWithTitle: "Ses çal",
                            target: self, action: #selector(toggleSound(_:)))
        sound.state = Preferences.shared.playSound ? .on : .off
        stack.addArrangedSubview(sound)

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        loginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        stack.addArrangedSubview(loginCheckbox)

        // 5) Geçmiş
        stack.addArrangedSubview(baslik("MENÜDE GÖSTERİLECEK GÖRÜNTÜ SAYISI"))
        let countPopup = NSPopUpButton()
        for n in [5, 10, 12, 20, 30, 50] { countPopup.addItem(withTitle: "\(n)") }
        let idx = [5, 10, 12, 20, 30, 50].firstIndex(of: Preferences.shared.historyCount) ?? 2
        countPopup.selectItem(at: idx)
        countPopup.target = self
        countPopup.action = #selector(countChanged(_:))
        stack.addArrangedSubview(countPopup)

        // 6) Test
        stack.addArrangedSubview(NSBox.dikeyAyrac())
        let testRow = NSStackView()
        testRow.orientation = .horizontal
        testRow.spacing = 10
        let test = NSButton(title: "Şimdi bir ekran görüntüsü al (test)",
                            target: self, action: #selector(testCapture))
        test.bezelStyle = .rounded
        testRow.addArrangedSubview(test)
        stack.addArrangedSubview(testRow)

        let info = NSTextField(wrappingLabelWithString:
            "İlk çalıştırmada macOS “Ekran Kaydı” izni isteyecek: Sistem Ayarları → "
            + "Gizlilik ve Güvenlik → Ekran Kaydı → Kodmoz Picture. "
            + "Kısayol erişilebilirlik izni GEREKTİRMEZ.")
        info.font = .systemFont(ofSize: 11)
        info.textColor = .tertiaryLabelColor
        info.widthAnchor.constraint(equalToConstant: 470).isActive = true
        stack.addArrangedSubview(info)

        // Pencereyi içeriğe göre boyutlandır; sabit yükseklik alt satırları kesiyordu.
        stack.bottomAnchor.constraint(greaterThanOrEqualTo: content.bottomAnchor,
                                      constant: -20).isActive = true
        content.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        if let win = window {
            let height = fitting.height + 40
            win.setContentSize(NSSize(width: max(520, fitting.width + 40), height: height))
            win.styleMask.insert(.resizable)
            win.contentMinSize = NSSize(width: 520, height: height)
            win.center()
        }
    }

    // MARK: - Eylemler

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Preferences.shared.saveFolder
        panel.prompt = "Seç"
        if panel.runModal() == .OK, let url = panel.url {
            Preferences.shared.saveFolder = url
            folderLabel.stringValue = url.path
        }
    }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(at: Preferences.shared.saveFolder,
                                                withIntermediateDirectories: true)
        NSWorkspace.shared.open(Preferences.shared.saveFolder)
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        if i >= 0 && i < CaptureMode.allCases.count {
            Preferences.shared.mode = CaptureMode.allCases[i]
        }
    }

    @objc private func countChanged(_ sender: NSPopUpButton) {
        if let v = Int(sender.titleOfSelectedItem ?? "12") {
            Preferences.shared.historyCount = v
        }
    }

    @objc private func toggleClipboard(_ sender: NSButton) {
        Preferences.shared.copyToClipboard = sender.state == .on
    }

    @objc private func toggleNotification(_ sender: NSButton) {
        Preferences.shared.showNotification = sender.state == .on
    }

    @objc private func toggleSound(_ sender: NSButton) {
        Preferences.shared.playSound = sender.state == .on
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("KodmozPicture: giriş öğesi değiştirilemedi — \(error)")
        }
        loginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func testCapture() {
        if let r = CaptureEngine.shared.capture(mode: Preferences.shared.mode) {
            NSWorkspace.shared.open(r.url)
        }
    }
}

extension NSBox {
    static func dikeyAyrac() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.widthAnchor.constraint(equalToConstant: 470).isActive = true
        return b
    }
}
