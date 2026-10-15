# Starfield for Windows, GDI (`Starfield.scr`)

Plain C + Win32 + GDI, one source file. No .NET, no WebView2, no Electron, no runtime to install:
the ~175 KB `.scr` links only DLLs that ship with Windows 10/11 (user32, gdi32, advapi32, dwmapi,
comctl32 and the built-in Universal CRT). Its strengths are size, zero dependencies and low overhead; the
[WebView2 version](../windows-webview/README.md) matches the browser page exactly and the
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

## Which Windows version?

All three build to a `Starfield.scr` with the same settings and behaviour; they differ in how they render.

| | [`windows-webview/`](../windows-webview/README.md) | [`windows-gdi/`](../windows-gdi/README.md) | [`windows-direct2d/`](../windows-direct2d/README.md) |
|---|---|---|---|
| Stack | C#/WinForms + WebView2 | C + Win32 + GDI | C++ + Direct2D/D3D11 |
| Rendering | HTML canvas, anti-aliased | CPU, not anti-aliased | GPU, anti-aliased |
| Look | Identical to `starfield.html` | Close port, slightly harsher | Close port, smooth |
| Refresh rate | Browser compositor | `DwmFlush` (compositor rate) | Per-monitor vsync, one thread each |
| Changing visuals | Edit the HTML/JS | Edit C | Edit C++ |
| Size | ~70 MB self-contained (or small + .NET runtime) | ~175 KB | ~300 KB |
| Needs on target PC | WebView2 Runtime (+ .NET runtime if framework-dependent) | Nothing | Nothing (Windows 10+) |
| Overhead | A browser engine per monitor | Light, CPU-bound at high res | Light, GPU-bound |
| Minimum Windows | 10 (WebView2) | 7 | 10 |
| Toolchain | .NET 8 SDK on Windows | MinGW-w64 (any OS) or MSVC | MinGW-w64 (any OS) or MSVC |

- **`windows-webview/`**: pick it for fidelity to the browser page and to iterate on one HTML/JS source.
- **`windows-gdi/`**: pick it for the smallest, most compatible file (works back to Windows 7, software-only).
- **`windows-direct2d/`**: pick it for smooth, anti-aliased, GPU-driven rendering on modern machines
  without any runtime dependency; best choice for high-resolution and high-refresh-rate monitors.

Settings are shared by the two native versions (`HKCU\Software\Starfield`); the WebView2 version stores
its own JSON in `%LOCALAPPDATA%\Starfield`.
