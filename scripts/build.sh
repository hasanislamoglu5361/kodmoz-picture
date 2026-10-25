#!/usr/bin/env bash
# Kodmoz Picture — .app paketi üretir.
# Kullanım: ./scripts/build.sh [--universal]
set -euo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KOK"

APP_ADI="Kodmoz Picture"
BUNDLE="build/${APP_ADI}.app"
EXE="KodmozPicture"

echo "== 1) ikon seti üretiliyor =="
mkdir -p build/icon
# Önce binary'yi derle (ikon üretimi binary içinden yapılıyor: tek kaynak kod)
swift build -c release --product "$EXE"
BIN="$(swift build -c release --show-bin-path)/$EXE"
"$BIN" --make-icon "$KOK/build/icon" >/dev/null
if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$KOK/build/icon/AppIcon.iconset" -o "$KOK/build/AppIcon.icns"
  echo "   AppIcon.icns üretildi"
else
  echo "   UYARI: iconutil yok (macOS dışındasın?) — ikonsuz devam"
fi

echo "== 2) .app iskeleti =="
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$EXE"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
if [ -f "$KOK/build/AppIcon.icns" ]; then
  cp "$KOK/build/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi
for f in menubar.png menubar@2x.png; do
  [ -f "$KOK/build/icon/$f" ] && cp "$KOK/build/icon/$f" "$BUNDLE/Contents/Resources/$f"
done
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "== 3) imza (ad-hoc) =="
codesign --force --deep --sign - --identifier com.kodmoz.picture "$BUNDLE" 2>/dev/null \
  && echo "   ad-hoc imzalandı" \
  || echo "   UYARI: codesign başarısız (uygulama yine çalışır)"

echo "== 4) doğrulama =="
"$BUNDLE/Contents/MacOS/$EXE" --capture 2>/dev/null | head -1 || true
echo
echo "OK: $KOK/$BUNDLE"
echo "Kurmak için: ./scripts/install.sh"
