#!/usr/bin/env bash
# Checks the built app extension: valid signature, sandbox entitlement, and that every class named in its
# Info.plist exists in the binary. (Registering it needs the app in /Applications, so that is manual.)
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/Starfield.app ] || ./build.sh
APPEX=build/Starfield.app/Contents/PlugIns/Starfield.appex
PLIST=$APPEX/Contents/Info.plist
fail() { echo "FAIL: $*" >&2; exit 1; }

codesign --verify --deep --strict build/Starfield.app || fail "bad signature"
codesign -d --entitlements :- "$APPEX" 2>/dev/null | grep -q com.apple.security.app-sandbox || fail "not sandboxed"
[ "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$PLIST")" = com.apple.screensaver ] || fail "wrong extension point"
for key in NSExtension.NSExtensionPrincipalClass ScreenSaverViewControllerClass ScreenSaverConfigurationSheetViewControllerClass; do
  cls=$(plutil -extract "$key" raw "$PLIST")
  strings -a "$APPEX/Contents/MacOS/Starfield" | grep -qx "$cls" || fail "$key: class $cls not in binary"
done
lipo -archs "$APPEX/Contents/MacOS/Starfield" | grep -q arm64 || fail "no arm64 slice"
echo "appex ok"
