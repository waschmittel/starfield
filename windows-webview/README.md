# Starfield for Windows, WebView2 (`Starfield.scr`)

C#/WinForms app hosting the page in WebView2 (no Electron). Its strength is rendering the **same HTML/canvas
page as the browser version**: anti-aliased, identical look, and visual changes are made once in HTML/JS.
If you need a tiny, dependency-free file instead, see the [GDI](../windows-gdi/README.md) or [Direct2D](../windows-direct2d/README.md) versions.

**Not yet built or tested**: it was written on a Mac without the .NET SDK, so expect small compile
fixes on the first build.

## Build

Requires the .NET 8 SDK on Windows.

```powershell
.\build.ps1                       # self-contained single file (~70 MB, runs anywhere)
.\build.ps1 -FrameworkDependent   # small; target PC needs the .NET 8 Desktop Runtime
```

Output: `dist\Starfield.scr`. The target PC needs the WebView2 Runtime (preinstalled on Windows 11).

## Install

Right-click `Starfield.scr` > **Install**, or copy it to `C:\Windows\System32`. Then choose it in
Screen Saver settings; **Settings...** opens the options dialog.

## Settings

Speed, trail length (0–4) and star density (50–5000), saved to
`%LOCALAPPDATA%\Starfield\settings.json`. Defaults: speed 6, trail 0.4, 1200 stars. The preview pane
caps stars at 300. WebView2 user data lives in `%LOCALAPPDATA%\Starfield\WebView2` (System32 is not writable).

## How it works

- Windows starts the `.scr` with `/s` (run), `/p <hwnd>` (preview inside the settings window) or `/c`
  (configure); no argument also opens settings. See `Program.cs`.
- `/s` opens one borderless, topmost window per monitor, each with its own WebView2.
- `starfield.html` (embedded as a resource) exposes `window.setConfig({speed, trailLength, starCount})`
  and `window.setPaused(bool)`; the host calls `setConfig` after navigation.
- Exit-on-input is done by polling the OS every 50 ms (cursor moved more than 6 px, any key or mouse
  button), with an 800 ms grace period. WebView2 owns its own input windows, so form events never fire.
- Unlike the macOS saver, this one does use the HTML file. If WebView2 ever shows the same
  hidden-page suspension seen on macOS, the fallback is the native-renderer approach in `../macos`.

## Files

`Program.cs` (arg handling), `SaverForm.cs` (saver window), `SettingsForm.cs` (options dialog),
`Settings.cs` (JSON persistence), `NativeMethods.cs` (Win32 P/Invoke), `starfield.html` (page).

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
