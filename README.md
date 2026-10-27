# Kodmoz Picture

macOS menü çubuğunda yaşayan, **global kısayolla ekran görüntüsü alan** küçük ama eksiksiz uygulama.
Aldığı görüntüyü **otomatik olarak panoya kopyalar**, `~/Pictures/KodmozPicture` klasörüne kaydeder
ve menü çubuğundaki simgeden **son görüntüleri küçük resimlerle** gösterir.

<p align="center">
  <img src="docs/logo-512.png" width="160" alt="Kodmoz Picture logosu">
</p>

## Özellikler

- **Global kısayol** (varsayılan `⌘⇧6`) — erişilebilirlik izni **gerektirmez** (Carbon `RegisterEventHotKey`)
- **Panoya otomatik kopyalama** — görüntü + dosya referansı birlikte yazılır (WhatsApp/Finder/Slack hedefleri dosyayı tanır)
- **Otomatik kayıt** — `~/Pictures/KodmozPicture/Kodmoz 2026-10-25 at 18.30.12.png` biçiminde, klasör değiştirilebilir
- **Dört yakalama modu** — tüm ekranlar (varsayılan), ana ekran (`-m`), alan seçimi (`-i`), pencere seçimi (`-w`)
- **Menü çubuğu geçmişi** — son N görüntü küçük resimle listelenir; tıkla → Önizleme'de aç,
  alt menüden **Panoya Kopyala / Finder'da Göster / Çöp Kutusuna Taşı**
- **Bildirim** — yakalanan görüntünün küçük önizlemesiyle bildirim banner'ı
- **Ayarlar penceresi** — kısayol kaydedici, klasör seçimi, mod, pano/bildirim/ses açma-kapama, geçmiş sayısı
- **Girişte otomatik başlat** — `SMAppService` ile (LaunchAgent dosyası elle kurcalanmaz)
- **Vektörel logo** — ikon ve menü simgesi kodda `NSBezierPath` ile çizilir; harici görsel dosyası yok
- **Dock'ta görünmez** (`LSUIElement`) — sadece menü çubuğu
- **CLI** — `KodmozPicture --capture [full|mainScreen|selection|window]`, `KodmozPicture --make-icon <dizin>`

## Logo

| Uygulama ikonu | Menü çubuğu (koyu/açık) |
|---|---|
| ![](docs/logo-128.png) | ![](docs/menubar-onizleme.png) |

Menü simgesi **template image**'dır: sistem koyu temada beyaz, açık temada siyah çizer.

## Kurulum (macOS 13+)

```bash
git clone https://github.com/hasanislamoglu5361/kodmoz-picture.git
cd kodmoz-picture
./scripts/install.sh
```

`install.sh` şunları yapar: `swift build -c release` → ikon seti (`.icns`) → `Kodmoz Picture.app`
paketi → çalışan kopyayı kapatır → `/Applications` → `lsregister` → uygulamayı başlatır.

Evrensel (Apple Silicon + Intel) paket için: `./scripts/build.sh --universal`

Derleme, varsa **Apple Development** imza kimliğini kullanır; böylece Ekran Kaydı izni
sonraki derlemelerde korunur. Kimlik yoksa ad-hoc imzalar ve macOS her derlemede izni
yeniden isteyebilir.

### İlk çalıştırma izni (tek sefer)

İlk kısayolda macOS **Ekran Kaydı** izni ister:

> Sistem Ayarları → Gizlilik ve Güvenlik → **Ekran Kaydı** → **Kodmoz Picture** ✓

Sonrasında elle bir şey yapmanız gerekmez: uygulama izni algıladığında kendini otomatik
yeniden başlatır. (Kısayol için erişilebilirlik izni **gerekmez**.)

## Kullanım

| Ne | Nasıl |
|---|---|
| Ekran görüntüsü | `⌘⇧6` (Ayarlar'dan değiştirilebilir) |
| Alan seçerek | Menü → *Alan Seçerek Al* |
| Pencere seçerek | Menü → *Pencere Seçerek Al* |
| Geçmiş | Menü çubuğu simgesi → *Son Görüntüler* |
| Klasör | Menü → *Klasörü Aç* |
| Ayarlar | Menü → *Ayarlar…* (`⌘,`) |

## Mimari

```
Sources/KodmozPicture/
  main.swift            giriş noktası + CLI (--capture / --make-icon)
  AppDelegate.swift     menü çubuğu, menü kurulumu, geçmiş, bildirim
  HotKey.swift          Carbon global kısayol (izin gerektirmez)
  CaptureEngine.swift   screencapture çağrısı, pano, dosya adlandırma, geçmiş listesi
  Preferences.swift     UserDefaults sarmalayıcısı + kısayol tanımı
  PreferencesWindow.swift  ayarlar arayüzü + kısayol kaydedici + SMAppService
  LogoRenderer.swift    vektörel logo (ikon + menü simgesi) ve .iconset üretimi
scripts/
  build.sh              .app paketi (ikon → bundle → imza), --universal desteği
  install.sh            derle + /Applications'a kur + başlat
  logo_onizleme.py      README için PNG önizleme (Swift çiziminin eşi)
```

Bağımlılık yok: yalnızca AppKit + Carbon + CoreGraphics + ServiceManagement + UserNotifications.
Ekran görüntüsü `/usr/sbin/screencapture` ile alınır (Apple'ın kendi aracı).

## Sorun giderme

- **Kısayol çalışmıyor** → başka bir uygulama `⌘⇧6`'yı kullanıyor olabilir; Ayarlar'dan başka kombinasyon seç.
  Kısayol kaydedilemezse menünün en üstünde uyarı satırı görünür.
- **Siyah/boş görüntü** → Ekran Kaydı izni verilmemiş; uygulama izni olmadığını algılayıp
  Sistem Ayarları'nı açar. İzin verdiğinizde kendini otomatik yeniden başlatır — elle kapat-aç gerekmez.
- **İzin verdiğim hâlde tekrar tekrar izin istiyor** → macOS izin kararını süreç başlarken okur;
  çalışan süreç izni göremez. Güncel sürüm izni algılayınca kendini yeniden başlatır ve uyarıyı
  çalışma başına bir kez gösterir. Anahtar açık göründüğü hâlde sorun sürüyorsa eski bir TCC kaydı
  kalmıştır (imza değişikliğinde olur): uyarıdaki **İzni Sıfırla** düğmesini kullanın ya da
  `tccutil reset ScreenCapture com.kodmoz.picture` çalıştırın.
- **"Uygulama hasarlı" uyarısı** → ad-hoc imza sonrası Gatekeeper uyarısı; `install.sh` karantinayı
  temizler. Elle kopyaladıysan: `xattr -dr com.apple.quarantine "/Applications/Kodmoz Picture.app"`.
- **Menü simgesi görünmüyor** → `killall SystemUIServer` veya uygulamayı yeniden başlat.
- **Bildirim çıkmıyor** → Sistem Ayarları → Bildirimler → Kodmoz Picture → *Bildirimlere izin ver*.
- **İki kopya çalışıyor** → `pkill -x KodmozPicture` sonra uygulamayı yeniden aç.

## Lisans

MIT — bkz. [LICENSE](LICENSE).

---

Geliştirme: [Hasan İslamoğlu](https://hasanislamoglu.com) · Kodmoz
