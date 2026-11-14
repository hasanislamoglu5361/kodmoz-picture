import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import QuartzCore

/// Fareyi izleyen canlı büyüteç.
///
/// Ekranın yalnızca imlecin çevresindeki küçük bir bölgesi yakalanır
/// (`CGWindowListCreateImage`, ~10 ms). Yakalama "mercek penceresinin
/// altından" istenir; böylece mercek kendi görüntüsünü yakalayıp sonsuz
/// aynaya dönüşmez. Yakalama arka planda çalışır, pencere 60 fps'te
/// imleci izler.
final class MagnifierController {
    static let shared = MagnifierController()

    /// Mercek çapı (pt).
    private let diameter: CGFloat = 240
    /// Yakalama hızı sınırı (saniyede ~30 kare).
    private let captureInterval: CFTimeInterval = 1.0 / 30.0

    private var zoomLevel: CGFloat = 3
    private var panel: LensPanel?
    private var lensView: LensView?
    private var timer: Timer?
    private var escapeHotKey: HotKey?
    private let captureQueue = DispatchQueue(label: "com.kodmoz.picture.magnifier",
                                             qos: .userInteractive)

    private var captureInFlight = false
    private var lastRequestTime: CFTimeInterval = 0
    private var lastAppliedCursor = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
    private var lastAppliedZoom: CGFloat = 0
    private var session = 0
    private var reportedFailure = false

    private(set) var isVisible = false

    private init() {
        zoomLevel = CGFloat(Preferences.shared.magnifierZoom)
    }

    var zoom: CGFloat {
        get { zoomLevel }
        set {
            let clamped = min(8, max(1.5, newValue))
            guard abs(clamped - zoomLevel) > 0.0001 else { return }
            zoomLevel = clamped
            Preferences.shared.magnifierZoom = Double(clamped)
            lensView?.setZoom(clamped)
        }
    }

    func toggle() {
        if isVisible { close() } else { open() }
    }

    func open() {
        guard !isVisible else { return }
        isVisible = true
        reportedFailure = false
        session += 1
        lastAppliedCursor = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        lastAppliedZoom = 0
        lastRequestTime = 0
        captureInFlight = false

        let view = LensView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        view.setZoom(zoomLevel)
        view.onClose = { [weak self] in self?.close() }
        view.onZoomDelta = { [weak self] delta in
            guard let self = self else { return }
            self.zoom = self.zoom * exp(delta)
        }

        let p = LensPanel(contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        p.contentView = view
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = false
        p.acceptsMouseMovedEvents = false

        panel = p
        lensView = view

        // ESC mercek açıkken global olarak dinlenir. Pencere klavye odağı
        // çalmadığı için alttaki uygulamada yazmaya devam edilebilir.
        escapeHotKey = HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0,
                              allowNoModifiers: true) { [weak self] in
            self?.close()
        }

        if let screen = screenUnderMouse() {
            position(p, on: screen, mouse: NSEvent.mouseLocation)
        }
        p.orderFrontRegardless()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func close() {
        guard isVisible else { return }
        isVisible = false
        session += 1
        timer?.invalidate()
        timer = nil
        escapeHotKey = nil
        panel?.orderOut(nil)
        captureInFlight = false
        reportedFailure = false
    }

    // MARK: - İzleme

    private func tick() {
        guard isVisible, let panel = panel, let screen = screenUnderMouse() else { return }
        let mouse = NSEvent.mouseLocation
        position(panel, on: screen, mouse: mouse)

        if lensView?.needsZoomLabelAnimation == true {
            lensView?.needsDisplay = true
        }

        let cursor = cgPoint(fromCocoa: mouse)
        let now = CACurrentMediaTime()
        guard !captureInFlight,
              now - lastRequestTime >= captureInterval,
              abs(zoomLevel - lastAppliedZoom) > 0.001
                || hypot(cursor.x - lastAppliedCursor.x,
                         cursor.y - lastAppliedCursor.y) > 0.4
        else { return }

        requestCapture(at: cursor, zoom: zoomLevel, windowNumber: panel.windowNumber)
    }

    private func requestCapture(at cursor: CGPoint, zoom: CGFloat, windowNumber: Int) {
        guard windowNumber > 0 else { return }
        let sampleSide = diameter / zoom
        let sampleRect = CGRect(x: cursor.x - sampleSide / 2,
                                y: cursor.y - sampleSide / 2,
                                width: sampleSide, height: sampleSide)
        let windowID = CGWindowID(windowNumber)
        let session = self.session

        captureInFlight = true
        lastRequestTime = CACurrentMediaTime()

        captureQueue.async { [weak self] in
            // Kendi penceremizin altını yakala: mercek görüntüsü içine girmez.
            let image = CGWindowListCreateImage(sampleRect, .optionOnScreenBelowWindow,
                                                windowID, [.bestResolution])
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard session == self.session, self.isVisible else { return }
                self.captureInFlight = false
                self.lastAppliedCursor = cursor
                self.lastAppliedZoom = zoom
                if let image = image {
                    self.lensView?.show(image: image, sampleRect: sampleRect,
                                        cursor: cursor, zoom: zoom)
                } else {
                    self.captureFailed()
                }
            }
        }
    }

    private func captureFailed() {
        guard !reportedFailure else { return }
        reportedFailure = true
        if !ScreenPermission.isGranted {
            close()
            if ScreenPermission.handleCaptureFailure() {
                ScreenPermission.presentAlert()
            }
        } else {
            NSLog("KodmozPicture: büyüteç görüntüsü yakalanamadı")
        }
    }

    // MARK: - Konum

    private func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Merceği imlecin üstüne ortalar; ekran kenarında tamamen görünür kalacak
    /// biçimde içeri kaydırır. İçerik her zaman imleç noktasında ortalanır.
    private func position(_ panel: NSPanel, on screen: NSScreen, mouse: NSPoint) {
        let f = screen.frame
        let x = min(max(mouse.x - diameter / 2, f.minX), f.maxX - diameter)
        let y = min(max(mouse.y - diameter / 2, f.minY), f.maxY - diameter)
        let origin = NSPoint(x: x, y: y)
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }

    /// Cocoa (sol alt köken) → CG ekran (sol üst köken) koordinatı.
    private func cgPoint(fromCocoa p: CGPoint) -> CGPoint {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY
            ?? NSScreen.main?.frame.maxY ?? 0
        return CGPoint(x: p.x, y: primaryMaxY - p.y)
    }
}

/// Klavye odağı çalmayan, her alanda görünen mercek paneli.
final class LensPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Mercek içeriğini çizen görünüm.
final class LensView: NSView {
    var onClose: (() -> Void)?
    var onZoomDelta: ((CGFloat) -> Void)?

    private var image: NSImage?
    private var imageRect: CGRect = .zero
    private var zoomText = "3×"
    private var zoomLabelDeadline: CFTimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setZoom(_ zoom: CGFloat) {
        zoomText = Self.zoomString(zoom)
        zoomLabelDeadline = CACurrentMediaTime() + 1.5
        needsDisplay = true
    }

    var needsZoomLabelAnimation: Bool {
        CACurrentMediaTime() < zoomLabelDeadline + 0.12
    }

    /// Yakalanan görüntüyü, görüntüdeki `cursor` noktası merceğin tam
    /// merkezine gelecek biçimde yerleştirir.
    func show(image cgImage: CGImage, sampleRect: CGRect, cursor: CGPoint, zoom: CGFloat) {
        image = NSImage(cgImage: cgImage,
                        size: NSSize(width: CGFloat(cgImage.width),
                                     height: CGFloat(cgImage.height)))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        imageRect = CGRect(
            x: center.x - (cursor.x - sampleRect.minX) * zoom,
            y: center.y - (sampleRect.maxY - cursor.y) * zoom,
            width: sampleRect.width * zoom,
            height: sampleRect.height * zoom)
        needsDisplay = true
    }

    // MARK: - Çizim

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        let b = bounds

        ctx.saveGraphicsState()
        NSBezierPath(ovalIn: b.insetBy(dx: 1.5, dy: 1.5)).addClip()
        NSColor.black.setFill()
        b.fill()
        if let image = image {
            ctx.imageInterpolation = .high
            image.draw(in: imageRect)
        }
        ctx.restoreGraphicsState()

        // Dış koyu hat: açık zeminlerde beyaz halka kaybolmasın.
        let outer = NSBezierPath(ovalIn: b.insetBy(dx: 1, dy: 1))
        outer.lineWidth = 2
        NSColor.black.withAlphaComponent(0.55).setStroke()
        outer.stroke()

        let ring = NSBezierPath(ovalIn: b.insetBy(dx: 3, dy: 3))
        ring.lineWidth = 2.5
        NSColor.white.withAlphaComponent(0.92).setStroke()
        ring.stroke()

        drawZoomLabel()
    }

    private func drawZoomLabel() {
        let remain = zoomLabelDeadline - CACurrentMediaTime()
        guard remain > 0 else { return }
        let alpha = CGFloat(min(1, max(0, remain / 0.35)))
        let text = zoomText as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        let textSize = text.size(withAttributes: attrs)
        let padX: CGFloat = 7
        let height: CGFloat = 17
        let rect = NSRect(x: bounds.midX - (textSize.width + padX * 2) / 2,
                          y: 11,
                          width: textSize.width + padX * 2,
                          height: height)
        NSColor.black.withAlphaComponent(0.5 * alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
        text.draw(at: NSPoint(x: rect.minX + padX,
                              y: rect.minY + (height - textSize.height) / 2),
                  withAttributes: attrs)
    }

    private static func zoomString(_ zoom: CGFloat) -> String {
        let f = NumberFormatter()
        f.locale = Locale.current
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        let s = f.string(from: NSNumber(value: Double(zoom))) ?? "\(zoom)"
        return s + "×"
    }

    // MARK: - Girdi

    override func mouseDown(with event: NSEvent) { onClose?() }
    override func rightMouseDown(with event: NSEvent) { onClose?() }

    override func scrollWheel(with event: NSEvent) {
        let raw = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
        guard raw != 0 else { return }
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 0.004 : 0.06
        onZoomDelta?(raw * factor)
    }

    override func magnify(with event: NSEvent) {
        onZoomDelta?(event.magnification * 1.5)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }
}
