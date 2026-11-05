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

- `Sources/StarfieldView.swift` is a native port of the algorithm in `../starfield.html`. The simulation runs
  on the CPU; drawing is done on the GPU by `Sources/MetalRenderer.swift` (a `CAMetalLayer`, one instanced
  quad per star, anti-aliased capsule in the fragment shader, native display resolution). The shader is
  compiled from source at runtime because the Command Line Tools have no `metal` compiler.
- If Metal is unavailable or the shader fails to build, the view falls back to a Core Graphics renderer
  (CPU, shared 4K backing-pixel budget across monitors).
- Frames are driven by a per-screen `CAMetalDisplayLink`, so it matches 60/120/144 Hz and ProMotion
  displays. It hands out a ready drawable per refresh; calling `nextDrawable()` from a plain
  `CADisplayLink` callback blocked the main thread and caused periodic stutter.
- Hot loops use raw buffers and the build uses `-Ounchecked`; array bounds checks caused stutter.

## Things learned the hard way

- **Needs an arm64e slice.** `legacyScreenSaver` is arm64e on Apple Silicon; a plain arm64 bundle is not
  loaded (no settings dialog, nothing renders). `build.sh` builds arm64e + x86_64. The Command Line Tools
  lack x86_64 Swift compatibility libraries for old deployment targets; `CAMetalDisplayLink` needs macOS 14 anyway.
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
