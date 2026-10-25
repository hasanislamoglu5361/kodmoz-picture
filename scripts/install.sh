#!/usr/bin/env bash
# Kodmoz Picture — derler, /Applications'a kurar, menü çubuğunda başlatır.
set -euo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ADI="Kodmoz Picture"
HEDEF="/Applications/${APP_ADI}.app"

say() { printf '\033[1;32m%s\033[0m\n' "$*"; }

say "== 1) derleme =="
"$KOK/scripts/build.sh"

say "== 2) /Applications'a kopyalanıyor =="
if [ -d "$HEDEF" ]; then
  osascript -e "tell application \"${APP_ADI}\" to quit" 2>/dev/null || true
  sleep 1
  rm -rf "$HEDEF"
fi
cp -R "$KOK/build/${APP_ADI}.app" "$HEDEF"
xattr -dr com.apple.quarantine "$HEDEF" 2>/dev/null || true

say "== 3) Launch Services / menü çubuğu tazeleme =="
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$HEDEF" 2>/dev/null || true
killall Dock 2>/dev/null || true

say "== 4) başlatılıyor =="
open "$HEDEF"
sleep 2
pgrep -x KodmozPicture >/dev/null && say "   çalışıyor (PID $(pgrep -x KodmozPicture | head -1))" \
  || echo "   UYARI: başlamadı — Console'da 'KodmozPicture' aramasına bak"

cat <<'NOT'

─────────────────────────────────────────────
Kurulum tamam. Yapılacaklar:
1) İlk kısayolda macOS "Ekran Kaydı" izni ister:
   Sistem Ayarları → Gizlilik ve Güvenlik → Ekran Kaydı → Kodmoz Picture ✓
   (İzin verdikten sonra uygulamayı bir kez kapat-aç.)
2) Menü çubuğundaki 📷 simgesine tıkla → "Son Görüntüler" geçmişi gösterir.
3) Varsayılan kısayol: ⌘⇧P · Alan seçimi: menüden.
4) Girişte otomatik başlatma: Ayarlar → "Girişte otomatik başlat".
NOT
