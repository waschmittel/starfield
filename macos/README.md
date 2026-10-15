# Starfield for macOS (`Starfield.saver`)

Native screensaver bundle written in Swift. No Xcode project; `build.sh` calls `swiftc` directly.

## Build and install

Requires the Xcode Command Line Tools.

```bash
./build.sh
open build/Starfield.saver      # or copy it to ~/Library/Screen Savers/
```

Then pick **Starfield** in System Settings > Screen Saver. **Options...** opens the settings sheet.
After replacing an installed saver, restart the host so it picks up the new binary:

```bash
killall legacyScreenSaver WallpaperAgent
```

## Settings

Speed, trail length (0–4) and star density (50–5000). Stored with `ScreenSaverDefaults`
(module `com.example.starfield.saver`). Defaults: speed 6, trail 0.4, 1200 stars. The preview pane
caps stars at 300.

## How it works

- `Sources/StarfieldView.swift` is a native Core Graphics port of the algorithm in `../starfield.html`.
- Frames are driven by a per-screen `CADisplayLink` (macOS 14+), so it matches 60/120/144 Hz and ProMotion
  displays. On macOS 13 it falls back to AppKit's 60 Hz timer.
- Hot loops use raw buffers and the build uses `-Ounchecked`; array bounds checks caused stutter.

## Things learned the hard way

- **Needs an arm64e slice.** `legacyScreenSaver` is arm64e on Apple Silicon; a plain arm64 bundle is not
  loaded (no settings dialog, nothing renders). `build.sh` builds arm64e + x86_64. The Command Line Tools
  lack x86_64 Swift compatibility libraries below macOS 13, hence the macOS 13 deployment target.
- **No web view.** A `WKWebView` was tried (HTML embedded with `loadHTMLString`; `file://` loads from the
  bundle rendered black). The saver host reports the page as hidden, which suspends
  `requestAnimationFrame` and later the whole web process, so the saver went black after a few seconds.
  Private WebKit switches did not fix it. The macOS saver therefore does not use any HTML;
  `../starfield.html` is only the reference for the algorithm.
- Debugging: `log stream --predicate 'process == "legacyScreenSaver"'`.

## Distribution

`build.sh` signs ad hoc, which is fine on the machine that built it. For other Macs, sign with a
Developer ID and notarize:

```bash
SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

The bundle identifier is `com.example.starfield.saver` (`Info.plist`); change it before distributing.

## Icon

`Resources/thumbnail.png` and `thumbnail@2x.png` are the picker thumbnails. Regenerate with:

```bash
swiftc make-thumbnail.swift -o /tmp/mkthumb && /tmp/mkthumb
```
