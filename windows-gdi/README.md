# Starfield for Windows, GDI (`Starfield.scr`)

Plain C + Win32 + GDI, one source file. No .NET, no Electron, no runtime to install:
the ~175 KB `.scr` links only DLLs that ship with Windows 10/11 (user32, gdi32, advapi32, dwmapi,
comctl32 and the built-in Universal CRT). Its strengths are size, zero dependencies and low overhead; the
[Direct2D version](../windows-direct2d/README.md) is GPU-accelerated and anti-aliased. This one wins on
size and compatibility (software rendering works back to Windows 7).

It was cross-compiled and checked for warnings on a Mac, but **has not been run on Windows yet**.

## Build

Either toolchain works:

```bash
./build.sh            # macOS/Linux: MinGW-w64 cross-compile (brew install mingw-w64)
```

```bat
build.bat             :: Windows: MSVC, from an "x64 Native Tools Command Prompt"
```

Output: `dist\Starfield.scr`.

## Install

Right-click `Starfield.scr` > **Install**, or copy it to `C:\Windows\System32`. Pick it in
Screen Saver settings; **Settings...** opens the options window.

## Settings

Speed (0.5–30), trail length (0–4, 0 = plain dots) and star density (50–5000), stored under
`HKCU\Software\Starfield` (`Speed10`, `Trail10`, `Stars`). Defaults: speed 6, trail 0.4, 1200 stars.
The preview pane caps stars at 300.

## How it works

- Windows starts the `.scr` with `/s` (run), `/p <hwnd>` (preview in the settings window) or `/c`
  (configure; also the no-argument case).
- `/s` opens one borderless topmost window per monitor. Each window has its own star state and a
  GDI back buffer, so it renders at that monitor's full pixel resolution (DPI-aware).
- Same algorithm as `../starfield.html`: perspective projection, 8 brightness buckets, trails drawn as
  short lines from the star's previous projected position, round-capped pens.
- Motion is time-based. The loop waits on `DwmFlush()` to sync to the display refresh, so it follows
  60/120/144 Hz. With mixed refresh rates all windows share the compositor's rate.
- Exit on key press, mouse click, mouse move over 6 px (after a 500 ms grace period) or loss of focus.
- GDI has no anti-aliasing, so stars and trails are slightly harsher than the macOS version; see
  `../windows-direct2d` for the anti-aliased, GPU-driven variant.

## Version Comparison

All versions share the same algorithm and settings (speed, trail length, star density); they differ in platform and how they render.

| | [HTML](../starfield.html) | [macOS](../macos/README.md) | [Windows GDI](../windows-gdi/README.md) | [Windows Direct2D](../windows-direct2d/README.md) |
|---|---|---|---|---|
| Type | Web page (also [hosted](https://waschmittel.github.io/starfield/)) | `Starfield.saver` | `Starfield.scr` | `Starfield.scr` |
| Stack | HTML + JS canvas | Swift + Core Graphics | C + Win32 + GDI | C++ + Direct2D/D3D11 |
| Rendering | Canvas 2D, anti-aliased | Core Graphics, anti-aliased | CPU, not anti-aliased | GPU, anti-aliased |
| Look | Reference | Close port | Close port, slightly harsher | Close port, smooth |
| Refresh rate | Browser (`requestAnimationFrame`) | Per-screen `CADisplayLink` (macOS 14+), 60 Hz timer on 13 | `DwmFlush` (compositor rate) | Per-monitor vsync, one thread each |
| Changing visuals | Edit the HTML/JS | Edit Swift | Edit C | Edit C++ |
| Needs on target PC | A modern browser | Nothing | Nothing | Nothing |
| Minimum OS | Any with a modern browser | macOS 13 | Windows 7 | Windows 10 |
| Toolchain | None | Xcode Command Line Tools | MinGW-w64 (any OS) or MSVC | MinGW-w64 (any OS) or MSVC |

- **HTML**: try it instantly in a browser; not a real screensaver (fullscreen mode just keeps the screen awake).
- **macOS**: the native screensaver for Macs.
- **Windows GDI**: the smallest, most compatible file (software-only, ~175 KB). **Use this one on old Windows versions.**
- **Windows Direct2D**: smooth, anti-aliased, GPU-driven rendering on Windows 10+ (~300 KB); best choice for
  high-resolution and high-refresh-rate monitors.

The two Windows versions share their settings (`HKCU\Software\Starfield`).
