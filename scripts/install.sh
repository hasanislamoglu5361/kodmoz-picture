#!/usr/bin/env bash
# Kodmoz Picture — derler, /Applications'a kurar, menü çubuğunda başlatır.
set -euo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ADI="Kodmoz Picture"
EXE="KodmozPicture"
HEDEF="/Applications/${APP_ADI}.app"

say() { printf '\033[1;32m%s\033[0m\n' "$*"; }
uyari() { printf '\033[1;33m%s\033[0m\n' "$*"; }

say "== 1) derleme =="
"$KOK/scripts/build.sh" "$@"

say "== 2) çalışan kopya kapatılıyor =="
if pgrep -x "$EXE" >/dev/null; then
  osascript -e "tell application \"${APP_ADI}\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -x "$EXE" >/dev/null || break
    sleep 1
  done
  if pgrep -x "$EXE" >/dev/null; then
    pkill -x "$EXE" 2>/dev/null || true
    sleep 1
  fi
  pgrep -x "$EXE" >/dev/null && { pkill -9 -x "$EXE" 2>/dev/null || true; sleep 1; }
  echo "   kapatıldı"
else
  echo "   çalışan kopya yok"
fi

say "== 3) /Applications'a kopyalanıyor =="
rm -rf "$HEDEF"
cp -R "$KOK/build/${APP_ADI}.app" "$HEDEF"
xattr -dr com.apple.quarantine "$HEDEF" 2>/dev/null || true

say "== 4) Launch Services kaydı =="
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$HEDEF" 2>/dev/null || true

say "== 5) başlatılıyor =="
open "$HEDEF"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if pgrep -x "$EXE" >/dev/null; then
    say "   çalışıyor (PID $(pgrep -x "$EXE" | head -1))"
    break
  fi
  sleep 1
done
if ! pgrep -x "$EXE" >/dev/null; then
  uyari "   UYARI: başlamadı — Console'da 'KodmozPicture' aramasına bak"
  uyari "   Doğrudan çalıştırıp hatayı görmek için:"
  uyari "   \"$HEDEF/Contents/MacOS/$EXE\""
fi

cat <<'NOT'

─────────────────────────────────────────────
Kurulum tamam. Yapılacaklar:
1) İlk kısayolda macOS "Ekran Kaydı" izni ister:
   Sistem Ayarları → Gizlilik ve Güvenlik → Ekran Kaydı → Kodmoz Picture ✓
   (İzin verdikten sonra uygulamayı bir kez kapat-aç.)
2) Menü çubuğundaki vizör simgesine tıkla → "Son Görüntüler" geçmişi gösterir.
3) Varsayılan kısayol: ⌘⇧P · Alan seçimi: menüden.
4) Girişte otomatik başlatma: Ayarlar → "Girişte otomatik başlat".
NOT
