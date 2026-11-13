#!/usr/bin/env bash
# Builds, into ./build, a universal Starfield.saver (legacy ScreenSaver plug-in) and Starfield.app (a host
# for the Starfield.appex app-extension screensaver, which is the format macOS itself is moving to).
# Optional: SIGN_ID="Developer ID Application: Name (TEAMID)" ./build.sh   (default: ad-hoc signature)
set -euo pipefail
cd "$(dirname "$0")"

SAVER=build/Starfield.saver
APP=build/Starfield.app
APPEX=$APP/Contents/PlugIns/Starfield.appex
rm -rf build
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources" \
         "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources" "$APP/Contents/MacOS" build/tmp

# compile <output> <archs> <swiftc args...>: builds each arch and lipos them together.
compile() {
  local out=$1 archs=$2 slices=() arch; shift 2
  for arch in $archs; do
    swiftc -Ounchecked -module-name Starfield \
      -target "$arch-apple-macos14.0" "$@" "-o" "build/tmp/$(basename "$out")-$arch"
    slices+=("build/tmp/$(basename "$out")-$arch")
  done
  lipo -create "${slices[@]}" -output "$out"
}

FRAMEWORKS=(-framework ScreenSaver -framework AppKit -framework Metal -framework QuartzCore)

# legacyScreenSaver is arm64e on Apple Silicon, so the plug-in must be too.
compile "$SAVER/Contents/MacOS/Starfield" "arm64e x86_64" -parse-as-library "${FRAMEWORKS[@]}" -Xlinker -bundle Sources/*.swift
cp Info.plist "$SAVER/Contents/Info.plist"
cp Resources/thumbnail.png Resources/thumbnail@2x.png ../LICENSE "$SAVER/Contents/Resources/"

# The extension runs in its own process, so plain arm64.
compile "$APPEX/Contents/MacOS/Starfield" "arm64 x86_64" -parse-as-library "${FRAMEWORKS[@]}" -application-extension \
  -import-objc-header Appex/ScreenSaverPrivate.h -Xlinker -e -Xlinker _NSExtensionMain \
  Sources/*.swift Appex/StarfieldExtension.swift
cp Appex/Info.plist "$APPEX/Contents/Info.plist"
cp Resources/thumbnail.png Resources/thumbnail@2x.png ../LICENSE "$APPEX/Contents/Resources/"

compile "$APP/Contents/MacOS/Starfield" "arm64 x86_64" -framework AppKit Appex/host.swift
cp Appex/Host-Info.plist "$APP/Contents/Info.plist"
rm -rf build/tmp

codesign --force --deep --sign "${SIGN_ID:--}" "$SAVER"
# Inside-out, and without --deep, which would drop the extension's own entitlements.
codesign --force --sign "${SIGN_ID:--}" --entitlements Appex/Extension.entitlements "$APPEX"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $SAVER and $APP"
echo "Install: open $SAVER   (legacy saver; or copy to ~/Library/Screen Savers/)"
echo "         open $APP     (app extension; registers it, then pick Starfield in System Settings)"
