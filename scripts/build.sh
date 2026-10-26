#!/usr/bin/env bash
# Kodmoz Picture — .app paketi üretir.
# Kullanım: ./scripts/build.sh [--universal]
#   --universal : hem arm64 hem x86_64 derle. Varsayılan: bu Mac'in mimarisi.
set -euo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KOK"

APP_ADI="Kodmoz Picture"
BUNDLE="build/${APP_ADI}.app"
EXE="KodmozPicture"
UNIVERSAL=0
[ "${1:-}" = "--universal" ] && UNIVERSAL=1

echo "== 1) derleme =="
BUILD_ARGS=(-c release --product "$EXE")
if [ "$UNIVERSAL" -eq 1 ]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
  echo "   hedef: arm64 + x86_64 (evrensel)"
fi
swift build "${BUILD_ARGS[@]}"

# --show-bin-path, --arch verildiğinde apple/Products/Release altını döndürür.
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$EXE"
[ -x "$BIN" ] || { echo "HATA: binary bulunamadı: $BIN" >&2; exit 1; }

echo "== 2) ikon seti üretiliyor =="
rm -rf build/icon
mkdir -p build/icon
"$BIN" --make-icon "$KOK/build/icon" >/dev/null
if command -v iconutil >/dev/null 2>&1; then
  rm -f build/AppIcon.icns
  iconutil -c icns "$KOK/build/icon/AppIcon.iconset" -o "$KOK/build/AppIcon.icns"
  echo "   AppIcon.icns üretildi"
else
  echo "   UYARI: iconutil yok (macOS dışındasın?) — ikonsuz devam"
fi

echo "== 3) .app iskeleti =="
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

# v1.2.3 biçimli git etiketi varsa sürümü Info.plist'e yaz.
if VERSION_TAG="$(git describe --tags --abbrev=0 2>/dev/null)" \
   && [[ "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION_TAG#v}" \
    "$BUNDLE/Contents/Info.plist" 2>/dev/null || true
  echo "   sürüm: ${VERSION_TAG#v} (git etiketi)"
fi

echo "== 4) imza =="
# Sabit bir kimlikle imzalamak Ekran Kaydı izninin sonraki derlemelerde
# korunmasını sağlar; ad-hoc imzada her derleme yeni uygulama sayılır.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
if [ -n "$IDENTITY" ] \
   && codesign --force --deep --sign "$IDENTITY" --identifier com.kodmoz.picture \
        --options runtime "$BUNDLE" >/dev/null 2>&1; then
  echo "   imzalandı: $IDENTITY"
elif codesign --force --deep --sign - --identifier com.kodmoz.picture "$BUNDLE" 2>/dev/null; then
  echo "   ad-hoc imzalandı (Ekran Kaydı izni her derlemede yenilenebilir)"
else
  echo "   UYARI: codesign başarısız (uygulama yine çalışır)"
fi

echo "== 5) doğrulama =="
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null && echo "   Info.plist geçerli"
test -x "$BUNDLE/Contents/MacOS/$EXE" && echo "   binary çalıştırılabilir"
codesign --verify --strict "$BUNDLE" 2>/dev/null && echo "   imza doğrulandı" \
  || echo "   UYARI: imza doğrulanamadı"
echo "   mimari: $(lipo -archs "$BUNDLE/Contents/MacOS/$EXE" 2>/dev/null || echo bilinmiyor)"
echo
echo "OK: $KOK/$BUNDLE"
echo "Kurmak için: ./scripts/install.sh"
