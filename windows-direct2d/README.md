# Starfield for Windows, Direct2D (`Starfield.scr`)

C++ + Direct2D on a D3D11/DXGI flip-model swap chain. GPU-accelerated and anti-aliased, with no .NET
and no runtime to install: the ~300 KB `.scr` links only system DLLs (`d2d1`, `d3d11`,
user32, gdi32, advapi32, comctl32). Needs **Windows 10 or later** (flip-model swap chains).

It was cross-compiled and checked for warnings on a Mac, but **has not been run on Windows yet**.

## Build

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
`HKCU\Software\Starfield` (`Speed10`, `Trail10`, `Stars`), the same key as `../windows-gdi`, so the two
share settings. Defaults: speed 6, trail 0.4, 1200 stars. The preview pane caps stars at 300.

## How it works

- Windows starts the `.scr` with `/s` (run), `/p <hwnd>` (preview) or `/c` (configure; also the
  no-argument case).
- `/s` opens one borderless topmost window per monitor and starts **one render thread per monitor**.
  Each thread owns its own D3D11 device, swap chain, Direct2D context and star state.
- Pacing: the swap chain is a waitable, frame-latency-1 flip-model chain and each frame ends with
  `Present(1, 0)`, so a thread blocks on *its own monitor's* vblank. A 144 Hz and a 60 Hz screen run
  independently at their native rates (the GDI version shares one compositor rate). Motion is
  time-based, so speed is identical at any refresh rate.
- Same algorithm as `../starfield.html`: perspective projection, 8 brightness buckets, trails as
  round-capped lines from the star's previous projected position (`DrawLine`), dots as anti-aliased
  ellipses (`FillEllipse`).
- The main thread only pumps window messages. Exit on key press, mouse click, mouse move over 6 px
  (after a 500 ms grace period) or loss of focus.
- If a hardware D3D11 device can't be created it falls back to the WARP software rasterizer. If the
  GPU is lost or setup fails entirely the saver exits instead of freezing on a black screen.

## Limitations

- Needs Windows 10+; use `../windows-gdi` for Windows 7/8.
- No device-lost recovery beyond exiting, and windows are not resizable (not needed for a saver).

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
