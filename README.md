# Starfield

Classic Windows-style starfield screensaver. For **Mac**, **Windows** and plain **HTML**

![Starfield screensaver](assets/starfield.png)

**[▶ Try the HTML version in your browser](https://waschmittel.github.io/starfield/)**

Prebuilt screensavers are on the [Releases page](https://github.com/waschmittel/starfield/releases):
macOS, Windows Direct2D (Windows 10/11) and Windows GDI (**use this one on old Windows versions**).

## HTML

- `starfield.html` – ([live demo](https://waschmittel.github.io/starfield/)) standalone interactive browser version. `F`/double-click fullscreen (keeps the
  screen awake), `↑ ↓`/wheel speed, `← →` trail length, `+ −` star density, `Space` pause.

## macOS
- `macos/` – native `Starfield.saver` (Swift). See [macos/README.md](macos/README.md).

## Windows

- `windows-webview/` – `Starfield.scr`, C#/WinForms + WebView2: renders the same HTML page as the browser. See [windows-webview/README.md](windows-webview/README.md).
- `windows-gdi/` – `Starfield.scr`, plain C/Win32/GDI: tiny, CPU-rendered, works back to Windows 7. See [windows-gdi/README.md](windows-gdi/README.md).
- `windows-direct2d/` – `Starfield.scr`, C++/Direct2D: GPU-accelerated, anti-aliased, per-monitor vsync. See [windows-direct2d/README.md](windows-direct2d/README.md).

`windows-webview/` has its own `starfield.html` (no UI, with `setConfig`/`setPaused` hooks) embedded by the
WebView2 host. The macOS, GDI and Direct2D savers don't use any HTML.

## Which Windows version?

All three build to a `Starfield.scr` with the same settings and behaviour; they differ in how they render.

| | [`windows-webview/`](windows-webview/README.md) | [`windows-gdi/`](windows-gdi/README.md) | [`windows-direct2d/`](windows-direct2d/README.md) |
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
