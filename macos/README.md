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

## App extension (`Starfield.app`)

`build.sh` also builds `build/Starfield.app`, which embeds `Starfield.appex`: the same saver as an **app
extension**, the format Apple's own savers use and the one the legacy host's view leaks don't affect.
The appex shares `Sources/` with the `.saver`; `Appex/` holds only what differs (the three framework
classes, `Info.plist`, sandbox entitlements, a host app that registers the extension).

> [!WARNING]
> The extension point (`com.apple.screensaver`) is **undocumented** for third parties, so this uses private
> API that can change in any macOS release, and can't be shipped through the Mac App Store. Keep using the
> `.saver` if you need the documented route. Declarations in `Appex/ScreenSaverPrivate.h` come from
> [AppexSaverMinimal](https://github.com/AerialScreensaver/AppexSaverMinimal).

Install: `brew install --cask waschmittel/starfield/starfield-app` (conflicts with the `starfield` cask), or copy `Starfield.app` to `/Applications` (PlugInKit rejects an extension in an arbitrary folder
until the app is known to LaunchServices) and open it once, then pick **Starfield** in System Settings
(Wallpaper > Screen Saver on macOS 26, Screen Saver before). Keep a single copy of the app on the machine, or
the system may load an unexpected one. After replacing it: `killall WallpaperAgent`.

- The extension is sandboxed; its settings live in its own container (`de.flubba.starfield.extension`), so
  they are separate from the `.saver`'s.
- The host never sends `stopAnimation` to views it releases, so the view also ends its session when it
  leaves its window. Unlike `legacyScreenSaver`, the Wallpaper agent really deallocates them.
- Untested here: the picker thumbnail (extensions normally ship it in an asset catalog, which needs Xcode;
  `CFBundleIconFile` is a best guess). Apart from registration, `tests/appex-check.sh` and the extension-style
  case in `tests/leak-check.sh` stand in for running it in the Wallpaper agent.

## Settings

Speed, trail length (0–4) and star density (50–5000). Stored with `ScreenSaverDefaults`
(module `de.flubba.starfield.saver`; for the extension `de.flubba.starfield.extension`). Defaults: speed 6, trail 0.4, 1200 stars. The preview pane
caps stars at 300.

## How it works

- `Sources/StarfieldView.swift` is a native port of the algorithm in `../starfield.html`. The simulation runs
  on the CPU; drawing is done on the GPU by `Sources/MetalRenderer.swift` (a `CAMetalLayer`, one instanced
  quad per star, anti-aliased capsule in the fragment shader, native display resolution). The shader is
  compiled from source at runtime because the Command Line Tools have no `metal` compiler.
- Without a usable Metal device (or if the shader fails to build) the saver shows a short message on a
  black screen and logs the specific reason (see Debugging below).
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
- **`legacyScreenSaver` leaks views.** Since macOS 14 the host never deallocates stopped `ScreenSaverView`s
  and rarely calls `stopAnimation` (the `com.apple.screensaver.willstop` notification is the real signal).
  Each view pinned its full-screen drawables, which added up to 10+ GB over days. The view now drops its
  renderer and layer on `willstop`/`stopAnimation` and rebuilds them in `startAnimation`.
  `tests/leak-check.sh` guards this (30 leaked views must stay under 500 MB; it was ~7.5 GB).
- Debugging: `log stream --predicate 'process == "legacyScreenSaver"'`.

## Distribution

`build.sh` signs ad hoc, which is fine on the machine that built it. For other Macs, sign with a
Developer ID and notarize:

```bash
SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

The bundle identifier is `de.flubba.starfield.saver` (`Info.plist`). It also names the settings domain, so changing it resets users' settings.

## Icon

`Resources/thumbnail.png` and `thumbnail@2x.png` are the picker thumbnails. Regenerate with:

```bash
swiftc make-thumbnail.swift -o /tmp/mkthumb && /tmp/mkthumb
```
