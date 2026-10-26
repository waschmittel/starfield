/*
 * Starfield screensaver, Direct2D on a D3D11/DXGI flip-model swap chain. GPU-accelerated and
 * anti-aliased, one render thread per monitor, each paced by its own display's vblank.
 * Only system DLLs (d2d1, d3d11, dxgi); needs Windows 10 or later (flip-model swap chains).
 *
 * Command line (Windows contract): /s run, /p <hwnd> preview, /c[:hwnd] or no argument = settings.
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <commctrl.h>
#include <d2d1_1.h>
#include <d3d11.h>
#include <dxgi1_3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wctype.h>

#define MAX_STARS      5000
#define BUCKETS        8
#define DEPTH          1000.0f
#define NEAR_Z         1.0f
#define SPREAD         2000.0f
#define PREVIEW_STARS  300
#define MOUSE_SLOP     6
#define GRACE_MS       500

#define REG_KEY L"Software\\Starfield"

struct Settings {
    float speed;        /* z units per 1/60 s */
    float trail;        /* 0..4 */
    int   stars;        /* 50..5000 */
};

static const Settings kDefaults = { 6.0f, 0.4f, 1200 };

/* ---------- settings (registry, stored as DWORDs: speed*10, trail*10, stars) ---------- */

static DWORD read_dword(HKEY k, const wchar_t *name, DWORD fallback) {
    DWORD v, sz = sizeof v, type;
    if (RegQueryValueExW(k, name, NULL, &type, (BYTE *)&v, &sz) == ERROR_SUCCESS && type == REG_DWORD) return v;
    return fallback;
}

static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
static int   clampi(int v, int lo, int hi)       { return v < lo ? lo : (v > hi ? hi : v); }

static Settings load_settings(void) {
    Settings s = kDefaults;
    HKEY k;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, REG_KEY, 0, KEY_READ, &k) == ERROR_SUCCESS) {
        s.speed = read_dword(k, L"Speed10", (DWORD)(kDefaults.speed * 10)) / 10.0f;
        s.trail = read_dword(k, L"Trail10", (DWORD)(kDefaults.trail * 10)) / 10.0f;
        s.stars = (int)read_dword(k, L"Stars", (DWORD)kDefaults.stars);
        RegCloseKey(k);
    }
    s.speed = clampf(s.speed, 0.5f, 30.0f);
    s.trail = clampf(s.trail, 0.0f, 4.0f);
    s.stars = clampi(s.stars, 50, MAX_STARS);
    return s;
}

static void save_settings(const Settings *s) {
    HKEY k;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, REG_KEY, 0, NULL, 0, KEY_WRITE, NULL, &k, NULL) != ERROR_SUCCESS) return;
    DWORD v;
    v = (DWORD)(s->speed * 10 + 0.5f); RegSetValueExW(k, L"Speed10", 0, REG_DWORD, (BYTE *)&v, sizeof v);
    v = (DWORD)(s->trail * 10 + 0.5f); RegSetValueExW(k, L"Trail10", 0, REG_DWORD, (BYTE *)&v, sizeof v);
    v = (DWORD)s->stars;               RegSetValueExW(k, L"Stars",   0, REG_DWORD, (BYTE *)&v, sizeof v);
    RegCloseKey(k);
}

/* ---------- starfield state and Direct2D renderer, one per monitor window ---------- */

template <class T> static void safe_release(T *&p) { if (p) { p->Release(); p = NULL; } }

struct Saver {
    HWND hwnd;
    int w, h, stars;
    float scale;                         /* line/dot size multiplier for high-res screens */
    HANDLE thread;
    unsigned rng;
    float x[MAX_STARS], y[MAX_STARS], z[MAX_STARS];
    float sx[MAX_STARS], sy[MAX_STARS], px[MAX_STARS], py[MAX_STARS], sz[MAX_STARS];
    int bidx[BUCKETS][MAX_STARS];
    int blen[BUCKETS];
};

static volatile LONG g_running = 1;
static Settings g_cfg;

static float frand(Saver *s) {            /* xorshift32 -> [0,1) */
    s->rng ^= s->rng << 13; s->rng ^= s->rng >> 17; s->rng ^= s->rng << 5;
    return (s->rng >> 8) * (1.0f / 16777216.0f);
}

static void respawn(Saver *s, int i, bool anywhere) {
    s->x[i] = (frand(s) - 0.5f) * SPREAD;
    s->y[i] = (frand(s) - 0.5f) * SPREAD;
    s->z[i] = anywhere ? frand(s) * DEPTH + NEAR_Z : DEPTH;
}

static void saver_step(Saver *s, float dt) {
    float cx = s->w / 2.0f, cy = s->h / 2.0f;
    float focal = (s->w > s->h ? s->w : s->h) * 0.5f;
    float stepz = g_cfg.speed * dt;
    float trailz = g_cfg.speed * g_cfg.trail;

    for (int b = 0; b < BUCKETS; b++) s->blen[b] = 0;
    for (int i = 0; i < s->stars; i++) {
        s->z[i] -= stepz;
        if (s->z[i] < NEAR_Z) { respawn(s, i, false); continue; }

        float z = s->z[i], k = focal / z;
        float sx = cx + s->x[i] * k, sy = cy + s->y[i] * k;
        if (sx < -50 || sx > s->w + 50 || sy < -50 || sy > s->h + 50) { respawn(s, i, false); continue; }

        float kp = focal / (z + trailz);
        s->sx[i] = sx; s->sy[i] = sy;
        s->px[i] = cx + s->x[i] * kp; s->py[i] = cy + s->y[i] * kp;

        float t = 1.0f - z / DEPTH;
        s->sz[i] = (0.6f + t * t * 2.6f) * s->scale;
        int b = (int)(t * BUCKETS);
        if (b >= BUCKETS) b = BUCKETS - 1;
        s->bidx[b][s->blen[b]++] = i;
    }
}

/* double: the counter runs from boot, a float would lose millisecond precision after hours of uptime
 * and make dt jitter visibly. */
static double now_seconds(void) {
    static LARGE_INTEGER freq;
    LARGE_INTEGER t;
    if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart / (double)freq.QuadPart;
}

/* Finds the adapter that has the given monitor attached, so a multi-GPU system renders each screen
 * on the GPU that scans it out (no cross-adapter copies). Returns NULL if not found. */
static IDXGIAdapter1 *find_adapter_for_monitor(HMONITOR mon) {
    IDXGIFactory1 *f = NULL;
    IDXGIAdapter1 *found = NULL;
    if (!mon || FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), (void **)&f))) return NULL;
    IDXGIAdapter1 *a = NULL;
    for (UINT i = 0; !found && f->EnumAdapters1(i, &a) != DXGI_ERROR_NOT_FOUND; i++) {
        IDXGIOutput *o = NULL;
        for (UINT j = 0; !found && a->EnumOutputs(j, &o) != DXGI_ERROR_NOT_FOUND; j++) {
            DXGI_OUTPUT_DESC od;
            if (SUCCEEDED(o->GetDesc(&od)) && od.Monitor == mon) { found = a; found->AddRef(); }
            o->Release();
        }
        a->Release();
    }
    f->Release();
    return found;
}

static HRESULT create_d3d_device(HMONITOR mon, ID3D11Device **dev) {
    D3D_FEATURE_LEVEL fl;
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    HRESULT hr = E_FAIL;
    IDXGIAdapter1 *adapter = find_adapter_for_monitor(mon);
    if (adapter) {
        hr = D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, NULL, flags, NULL, 0, D3D11_SDK_VERSION, dev, &fl, NULL);
        adapter->Release();
    }
    if (FAILED(hr))
        hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, flags, NULL, 0, D3D11_SDK_VERSION, dev, &fl, NULL);
    if (FAILED(hr))   /* no GPU / driver problem: software rasterizer still works, just slower */
        hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_WARP, NULL, flags, NULL, 0, D3D11_SDK_VERSION, dev, &fl, NULL);
    return hr;
}

/* Each monitor gets its own thread, device and swap chain. Present(1) then blocks on that monitor's
 * vblank only, so a 144 Hz and a 60 Hz screen each run at their own rate. */
static DWORD WINAPI render_thread(LPVOID param) {
    Saver *s = (Saver *)param;

    ID3D11Device *d3d = NULL;
    IDXGIDevice *dxgiDev = NULL;
    IDXGIAdapter *adapter = NULL;
    IDXGIFactory2 *factory = NULL;
    IDXGISwapChain1 *sc1 = NULL;
    IDXGISwapChain2 *sc = NULL;
    ID2D1Factory1 *d2dFactory = NULL;
    ID2D1Device *d2dDev = NULL;
    ID2D1DeviceContext *dc = NULL;
    ID2D1StrokeStyle *stroke = NULL;
    ID2D1SolidColorBrush *brushes[BUCKETS] = { 0 };
    HANDLE waitable = NULL;

    bool ok = SUCCEEDED(create_d3d_device(MonitorFromWindow(s->hwnd, MONITOR_DEFAULTTONEAREST), &d3d))
        && SUCCEEDED(d3d->QueryInterface(__uuidof(IDXGIDevice), (void **)&dxgiDev))
        && SUCCEEDED(dxgiDev->GetAdapter(&adapter))
        && SUCCEEDED(adapter->GetParent(__uuidof(IDXGIFactory2), (void **)&factory));

    if (ok) {
        DXGI_SWAP_CHAIN_DESC1 d = {};
        d.Width = s->w; d.Height = s->h;
        d.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        d.SampleDesc.Count = 1;
        d.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        d.BufferCount = 2;
        d.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
        d.Flags = DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT;
        ok = SUCCEEDED(factory->CreateSwapChainForHwnd(d3d, s->hwnd, &d, NULL, NULL, &sc1))
            && SUCCEEDED(sc1->QueryInterface(__uuidof(IDXGISwapChain2), (void **)&sc));
    }
    if (ok) {
        sc->SetMaximumFrameLatency(1);
        waitable = sc->GetFrameLatencyWaitableObject();
        ok = SUCCEEDED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory1), NULL, (void **)&d2dFactory))
            && SUCCEEDED(d2dFactory->CreateDevice(dxgiDev, &d2dDev))
            && SUCCEEDED(d2dDev->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &dc));
    }
    if (ok) {
        dc->SetDpi(96.0f, 96.0f);          /* 1 unit = 1 pixel */
        D2D1_STROKE_STYLE_PROPERTIES sp = D2D1::StrokeStyleProperties(
            D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_LINE_JOIN_ROUND);
        d2dFactory->CreateStrokeStyle(sp, NULL, 0, &stroke);
        for (int b = 0; b < BUCKETS; b++) {
            float v = (70.0f + 185.0f * b / (BUCKETS - 1)) / 255.0f;
            dc->CreateSolidColorBrush(D2D1::ColorF(v, v, v), &brushes[b]);
        }
    }

    double last = now_seconds();
    while (ok && g_running) {
        if (waitable) WaitForSingleObjectEx(waitable, 100, TRUE);
        if (!g_running) break;

        double t = now_seconds();
        float dt = (float)((t - last) * 60.0);   /* time-based: same speed at any refresh rate */
        last = t;
        if (dt > 4.0f) dt = 4.0f;
        saver_step(s, dt);

        IDXGISurface *surface = NULL;
        ID2D1Bitmap1 *target = NULL;
        if (FAILED(sc->GetBuffer(0, __uuidof(IDXGISurface), (void **)&surface))) break;
        D2D1_BITMAP_PROPERTIES1 bp = D2D1::BitmapProperties1(
            D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE), 96.0f, 96.0f);
        HRESULT hr = dc->CreateBitmapFromDxgiSurface(surface, &bp, &target);
        surface->Release();
        if (FAILED(hr)) break;

        dc->SetTarget(target);
        dc->BeginDraw();
        dc->Clear(D2D1::ColorF(0, 0, 0));
        for (int b = 0; b < BUCKETS; b++) {
            int n = s->blen[b];
            if (!n) continue;
            float lw = (0.6f + (float)b / (BUCKETS - 1) * 2.4f) * s->scale;
            for (int j = 0; j < n; j++) {
                int i = s->bidx[b][j];
                if (g_cfg.trail > 0.0f)
                    dc->DrawLine(D2D1::Point2F(s->px[i], s->py[i]), D2D1::Point2F(s->sx[i], s->sy[i]), brushes[b], lw, stroke);
                else
                    dc->FillEllipse(D2D1::Ellipse(D2D1::Point2F(s->sx[i], s->sy[i]), s->sz[i] / 2, s->sz[i] / 2), brushes[b]);
            }
        }
        hr = dc->EndDraw();
        dc->SetTarget(NULL);
        target->Release();
        if (FAILED(hr)) break;

        hr = sc->Present(1, 0);                /* vsync */
        if (FAILED(hr)) break;
    }

    for (int b = 0; b < BUCKETS; b++) safe_release(brushes[b]);
    safe_release(stroke);
    safe_release(dc);
    safe_release(d2dDev);
    safe_release(d2dFactory);
    safe_release(sc);
    safe_release(sc1);
    safe_release(factory);
    safe_release(adapter);
    safe_release(dxgiDev);
    safe_release(d3d);
    if (!ok) InterlockedExchange(&g_running, 0);   /* nothing to show: exit instead of a frozen window */
    return 0;
}

/* ---------- saver windows ---------- */

static const wchar_t *kSaverClass = L"StarfieldSaverWindow";
static bool g_preview = false;
static DWORD g_startTick;
static POINT g_startCursor;
static bool g_haveCursor;

static LRESULT CALLBACK saver_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_SETCURSOR:
        SetCursor(NULL);
        return TRUE;
    case WM_ERASEBKGND:
        return 1;
    case WM_KEYDOWN: case WM_SYSKEYDOWN:
    case WM_LBUTTONDOWN: case WM_RBUTTONDOWN: case WM_MBUTTONDOWN:
        if (!g_preview) InterlockedExchange(&g_running, 0);
        return 0;
    case WM_MOUSEMOVE:
        if (!g_preview) {
            POINT p; GetCursorPos(&p);
            if (!g_haveCursor) { g_startCursor = p; g_haveCursor = true; }
            else if (GetTickCount() - g_startTick > GRACE_MS &&
                     (abs(p.x - g_startCursor.x) > MOUSE_SLOP || abs(p.y - g_startCursor.y) > MOUSE_SLOP))
                InterlockedExchange(&g_running, 0);
        }
        return 0;
    case WM_ACTIVATEAPP:
        if (!wp && !g_preview && GetTickCount() - g_startTick > GRACE_MS) InterlockedExchange(&g_running, 0);
        return 0;
    case WM_SYSCOMMAND:
        if ((wp & 0xFFF0) == SC_SCREENSAVE || (wp & 0xFFF0) == SC_MONITORPOWER) return 0;
        break;
    case WM_CLOSE:
        InterlockedExchange(&g_running, 0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static int g_monCount;
static RECT g_monRects[16];

static BOOL CALLBACK monitor_cb(HMONITOR m, HDC dc, LPRECT r, LPARAM lp) {
    (void)m; (void)dc; (void)lp;
    if (g_monCount < 16) g_monRects[g_monCount++] = *r;
    return TRUE;
}

static Saver *make_saver(HWND hwnd, int stars) {
    Saver *s = (Saver *)calloc(1, sizeof(Saver));
    RECT r;
    GetClientRect(hwnd, &r);
    s->hwnd = hwnd;
    s->w = r.right - r.left;
    s->h = r.bottom - r.top;
    s->stars = stars;
    s->scale = s->h > 900 ? s->h / 900.0f : 1.0f;
    s->rng = 2463534242u ^ (unsigned)(UINT_PTR)hwnd;
    for (int i = 0; i < MAX_STARS; i++) respawn(s, i, true);
    return s;
}

static int run_saver(HINSTANCE inst, HWND previewParent) {
    g_cfg = load_settings();
    g_preview = previewParent != NULL;

    WNDCLASSW wc = {};
    wc.lpfnWndProc = saver_proc;
    wc.hInstance = inst;
    wc.lpszClassName = kSaverClass;
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    RegisterClassW(&wc);

    Saver *savers[16];
    int count = 0;
    if (g_preview) {
        RECT pr; GetClientRect(previewParent, &pr);
        HWND h = CreateWindowExW(0, kSaverClass, L"Starfield", WS_CHILD | WS_VISIBLE, 0, 0,
                                 pr.right - pr.left, pr.bottom - pr.top, previewParent, NULL, inst, NULL);
        if (!h) return 1;
        savers[count++] = make_saver(h, g_cfg.stars < PREVIEW_STARS ? g_cfg.stars : PREVIEW_STARS);
    } else {
        EnumDisplayMonitors(NULL, NULL, monitor_cb, 0);
        for (int i = 0; i < g_monCount; i++) {
            RECT r = g_monRects[i];
            HWND h = CreateWindowExW(WS_EX_TOPMOST, kSaverClass, L"Starfield", WS_POPUP | WS_VISIBLE,
                                     r.left, r.top, r.right - r.left, r.bottom - r.top, NULL, NULL, inst, NULL);
            if (h) savers[count++] = make_saver(h, g_cfg.stars);
        }
        if (!count) return 1;
        ShowCursor(FALSE);
    }
    g_startTick = GetTickCount();

    HANDLE threads[16];
    for (int i = 0; i < count; i++) {
        savers[i]->thread = CreateThread(NULL, 0, render_thread, savers[i], 0, NULL);
        threads[i] = savers[i]->thread;
    }

    /* The main thread only pumps window messages; rendering lives on the per-monitor threads. */
    while (g_running) {
        MSG m;
        while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) {
            if (m.message == WM_QUIT) InterlockedExchange(&g_running, 0);
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
        if (g_preview && !IsWindow(previewParent)) break;
        MsgWaitForMultipleObjects(0, NULL, FALSE, 50, QS_ALLINPUT);
    }

    InterlockedExchange(&g_running, 0);
    WaitForMultipleObjects(count, threads, TRUE, 3000);
    for (int i = 0; i < count; i++) {
        CloseHandle(savers[i]->thread);
        DestroyWindow(savers[i]->hwnd);
        free(savers[i]);
    }
    if (!g_preview) ShowCursor(TRUE);
    return 0;
}

/* ---------- settings dialog (plain window with trackbars, no resource file needed) ---------- */

enum { ID_SPEED = 101, ID_TRAIL, ID_STARS, ID_LSPEED, ID_LTRAIL, ID_LSTARS };

static Settings g_dlg;
static HWND g_tb[3], g_lbl[3];

static void update_labels(void) {
    wchar_t buf[32];
    swprintf(buf, 32, L"%.1f", SendMessageW(g_tb[0], TBM_GETPOS, 0, 0) / 10.0);
    SetWindowTextW(g_lbl[0], buf);
    swprintf(buf, 32, L"%.1f", SendMessageW(g_tb[1], TBM_GETPOS, 0, 0) / 10.0);
    SetWindowTextW(g_lbl[1], buf);
    swprintf(buf, 32, L"%d", (int)SendMessageW(g_tb[2], TBM_GETPOS, 0, 0));
    SetWindowTextW(g_lbl[2], buf);
}

static LRESULT CALLBACK config_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_CREATE: {
        HFONT font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
        static const wchar_t *names[3] = { L"Speed", L"Trail length", L"Star density" };
        static const int lo[3] = { 5, 0, 50 }, hi[3] = { 300, 40, MAX_STARS };
        int pos[3] = { (int)(g_dlg.speed * 10 + 0.5f), (int)(g_dlg.trail * 10 + 0.5f), g_dlg.stars };
        for (int i = 0; i < 3; i++) {
            int y = 16 + i * 44;
            HWND cap = CreateWindowW(L"STATIC", names[i], WS_CHILD | WS_VISIBLE, 16, y + 4, 90, 20, hwnd, NULL, NULL, NULL);
            g_tb[i] = CreateWindowW(TRACKBAR_CLASSW, L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_AUTOTICKS,
                                    110, y, 200, 32, hwnd, (HMENU)(INT_PTR)(ID_SPEED + i), NULL, NULL);
            g_lbl[i] = CreateWindowW(L"STATIC", L"", WS_CHILD | WS_VISIBLE, 320, y + 4, 50, 20, hwnd, NULL, NULL, NULL);
            SendMessageW(g_tb[i], TBM_SETRANGE, TRUE, MAKELPARAM(lo[i], hi[i]));
            SendMessageW(g_tb[i], TBM_SETPOS, TRUE, clampi(pos[i], lo[i], hi[i]));
            SendMessageW(cap, WM_SETFONT, (WPARAM)font, TRUE);
            SendMessageW(g_lbl[i], WM_SETFONT, (WPARAM)font, TRUE);
        }
        SendMessageW(g_tb[2], TBM_SETLINESIZE, 0, 50);
        SendMessageW(g_tb[2], TBM_SETPAGESIZE, 0, 250);
        SendMessageW(g_tb[2], TBM_SETTICFREQ, 500, 0);
        HWND ok = CreateWindowW(L"BUTTON", L"OK", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON | WS_TABSTOP, 210, 156, 76, 26, hwnd, (HMENU)IDOK, NULL, NULL);
        HWND cancel = CreateWindowW(L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE | WS_TABSTOP, 294, 156, 76, 26, hwnd, (HMENU)IDCANCEL, NULL, NULL);
        SendMessageW(ok, WM_SETFONT, (WPARAM)font, TRUE);
        SendMessageW(cancel, WM_SETFONT, (WPARAM)font, TRUE);
        update_labels();
        return 0;
    }
    case WM_HSCROLL:
        update_labels();
        return 0;
    case WM_COMMAND:
        if (LOWORD(wp) == IDOK) {
            Settings s;
            s.speed = SendMessageW(g_tb[0], TBM_GETPOS, 0, 0) / 10.0f;
            s.trail = SendMessageW(g_tb[1], TBM_GETPOS, 0, 0) / 10.0f;
            s.stars = (int)SendMessageW(g_tb[2], TBM_GETPOS, 0, 0);
            save_settings(&s);
            DestroyWindow(hwnd);
        } else if (LOWORD(wp) == IDCANCEL) {
            DestroyWindow(hwnd);
        }
        return 0;
    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static int run_config(HINSTANCE inst) {
    INITCOMMONCONTROLSEX icc = { sizeof icc, ICC_BAR_CLASSES };
    InitCommonControlsEx(&icc);
    g_dlg = load_settings();

    WNDCLASSW wc = {};
    wc.lpfnWndProc = config_proc;
    wc.hInstance = inst;
    wc.lpszClassName = L"StarfieldConfigWindow";
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    RegisterClassW(&wc);

    RECT r = { 0, 0, 390, 198 };
    DWORD style = WS_CAPTION | WS_SYSMENU;
    AdjustWindowRect(&r, style, FALSE);
    int w = r.right - r.left, h = r.bottom - r.top;
    int x = (GetSystemMetrics(SM_CXSCREEN) - w) / 2, y = (GetSystemMetrics(SM_CYSCREEN) - h) / 2;
    HWND hwnd = CreateWindowW(wc.lpszClassName, L"Starfield Settings", style | WS_VISIBLE, x, y, w, h, NULL, NULL, inst, NULL);
    if (!hwnd) return 1;

    MSG m;
    while (GetMessageW(&m, NULL, 0, 0) > 0) {
        if (!IsDialogMessageW(hwnd, &m)) { TranslateMessage(&m); DispatchMessageW(&m); }
    }
    return 0;
}

/* ---------- entry point ---------- */

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, LPWSTR cmd, int show) {
    (void)prev; (void)show;
    SetProcessDPIAware();                     /* full-resolution pixels, not scaled */

    while (*cmd == L' ' || *cmd == L'\t') cmd++;
    wchar_t mode = 'c';
    HWND arg = NULL;
    if (*cmd == L'/' || *cmd == L'-') {
        mode = (wchar_t)towlower(cmd[1]);
        const wchar_t *rest = cmd + 2;
        if (*rest == L':') rest++;
        while (*rest == L' ') rest++;
        if (*rest) arg = (HWND)(UINT_PTR)_wcstoui64(rest, NULL, 10);
    }

    switch (mode) {
    case 's': return run_saver(inst, NULL);
    case 'p': return arg ? run_saver(inst, arg) : 0;
    default:  return run_config(inst);
    }
}
