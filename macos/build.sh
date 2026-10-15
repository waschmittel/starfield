#!/usr/bin/env bash
# Builds a universal Starfield.saver into ./build.
# Optional: SIGN_ID="Developer ID Application: Name (TEAMID)" ./build.sh   (default: ad-hoc signature)
set -euo pipefail
cd "$(dirname "$0")"

OUT=build/Starfield.saver
rm -rf build
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" build/tmp

for arch in arm64e x86_64; do
  swiftc -Ounchecked -parse-as-library -module-name Starfield \
    -target "$arch-apple-macos13.0" \
    -framework ScreenSaver -framework AppKit \
    -Xlinker -bundle \
    Sources/StarfieldView.swift -o "build/tmp/Starfield-$arch"
done
lipo -create build/tmp/Starfield-arm64e build/tmp/Starfield-x86_64 -output "$OUT/Contents/MacOS/Starfield"

cp Info.plist "$OUT/Contents/Info.plist"
cp Resources/thumbnail.png Resources/thumbnail@2x.png "$OUT/Contents/Resources/"
rm -rf build/tmp

codesign --force --deep --sign "${SIGN_ID:--}" "$OUT"
echo "Built $OUT"
echo "Install: open $OUT   (or copy to ~/Library/Screen Savers/)"
