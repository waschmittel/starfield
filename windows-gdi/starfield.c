// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * Starfield screensaver, plain Win32 + GDI. No .NET, no CRT DLL:
 * only system DLLs that ship with Windows. Build to Starfield.scr (see build.bat / README.md).
 *
 * Command line (Windows contract): /s run, /p <hwnd> preview, /c[:hwnd] or no argument = settings.
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
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

typedef struct {
    float speed;        /* z units per 1/60 s */
    float trail;        /* 0..4 */
    int   stars;        /* 50..5000 */
} Settings;

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

/* ---------- starfield state, one per window ---------- */

typedef struct {
    HWND hwnd;
    int w, h;
    HDC mem;
    HBITMAP bmp, oldBmp;
    HPEN pens[BUCKETS];
    HBRUSH brushes[BUCKETS];
    HPEN oldPen;
    float scale;                         /* line/dot size multiplier for high-res screens */
    int stars;
    float x[MAX_STARS], y[MAX_STARS], z[MAX_STARS];
    float sx[MAX_STARS], sy[MAX_STARS], px[MAX_STARS], py[MAX_STARS], sz[MAX_STARS];
    int bidx[BUCKETS][MAX_STARS];
    int blen[BUCKETS];
} Saver;

static unsigned rng_state = 2463534242u;
static float frand(void) {                /* xorshift32 -> [0,1) */
    rng_state ^= rng_state << 13; rng_state ^= rng_state >> 17; rng_state ^= rng_state << 5;
    return (rng_state >> 8) * (1.0f / 16777216.0f);
}

static void respawn(Saver *s, int i, int anywhere) {
    s->x[i] = (frand() - 0.5f) * SPREAD;
    s->y[i] = (frand() - 0.5f) * SPREAD;
    s->z[i] = anywhere ? frand() * DEPTH + NEAR_Z : DEPTH;
}

static COLORREF bucket_color(int b) {
    int v = (int)(70 + 185.0 * b / (BUCKETS - 1) + 0.5);
    return RGB(v, v, v);
}

static void saver_init(Saver *s, HWND hwnd, int stars) {
    RECT r;
    GetClientRect(hwnd, &r);
    s->hwnd = hwnd;
    s->w = r.right - r.left;
    s->h = r.bottom - r.top;
    s->stars = stars;
    s->scale = s->h > 900 ? s->h / 900.0f : 1.0f;

    HDC dc = GetDC(hwnd);
    s->mem = CreateCompatibleDC(dc);
    s->bmp = CreateCompatibleBitmap(dc, s->w, s->h);
    s->oldBmp = (HBITMAP)SelectObject(s->mem, s->bmp);
    ReleaseDC(hwnd, dc);

    for (int b = 0; b < BUCKETS; b++) {
        float lw = (0.6f + (float)b / (BUCKETS - 1) * 2.4f) * s->scale;
        LOGBRUSH lb = { BS_SOLID, bucket_color(b), 0 };
        s->pens[b] = ExtCreatePen(PS_GEOMETRIC | PS_SOLID | PS_ENDCAP_ROUND, (DWORD)(lw + 0.5f), &lb, 0, NULL);
        s->brushes[b] = CreateSolidBrush(bucket_color(b));
    }
    s->oldPen = (HPEN)GetCurrentObject(s->mem, OBJ_PEN);
    for (int i = 0; i < MAX_STARS; i++) respawn(s, i, 1);
}

static void saver_free(Saver *s) {
    SelectObject(s->mem, s->oldPen);
    SelectObject(s->mem, s->oldBmp);
    DeleteObject(s->bmp);
    DeleteDC(s->mem);
    for (int b = 0; b < BUCKETS; b++) { DeleteObject(s->pens[b]); DeleteObject(s->brushes[b]); }
}

static void saver_step(Saver *s, float dt, const Settings *cfg) {
    float cx = s->w / 2.0f, cy = s->h / 2.0f;
    float focal = (s->w > s->h ? s->w : s->h) * 0.5f;
    float stepz = cfg->speed * dt;
    float trailz = cfg->speed * cfg->trail;

    for (int b = 0; b < BUCKETS; b++) s->blen[b] = 0;
    for (int i = 0; i < s->stars; i++) {
        s->z[i] -= stepz;
        if (s->z[i] < NEAR_Z) { respawn(s, i, 0); continue; }

        float z = s->z[i], k = focal / z;
        float sx = cx + s->x[i] * k, sy = cy + s->y[i] * k;
        if (sx < -50 || sx > s->w + 50 || sy < -50 || sy > s->h + 50) { respawn(s, i, 0); continue; }

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

static void saver_draw(Saver *s, const Settings *cfg) {
    RECT all = { 0, 0, s->w, s->h };
    FillRect(s->mem, &all, (HBRUSH)GetStockObject(BLACK_BRUSH));

    for (int b = 0; b < BUCKETS; b++) {
        int n = s->blen[b];
        if (!n) continue;
        const int *idx = s->bidx[b];
        if (cfg->trail > 0.0f) {
            SelectObject(s->mem, s->pens[b]);
            for (int j = 0; j < n; j++) {
                int i = idx[j];
                MoveToEx(s->mem, (int)(s->px[i] + 0.5f), (int)(s->py[i] + 0.5f), NULL);
                LineTo(s->mem, (int)(s->sx[i] + 0.5f), (int)(s->sy[i] + 0.5f));
            }
        } else {
            for (int j = 0; j < n; j++) {
                int i = idx[j];
                int sz = (int)(s->sz[i] + 0.5f);
                if (sz < 1) sz = 1;
                RECT r = { (int)(s->sx[i] - sz / 2.0f), (int)(s->sy[i] - sz / 2.0f), 0, 0 };
                r.right = r.left + sz; r.bottom = r.top + sz;
                FillRect(s->mem, &r, s->brushes[b]);
            }
        }
    }
}

static void saver_present(Saver *s) {
    HDC dc = GetDC(s->hwnd);
    BitBlt(dc, 0, 0, s->w, s->h, s->mem, 0, 0, SRCCOPY);
    ReleaseDC(s->hwnd, dc);
}

/* ---------- saver windows ---------- */

static const wchar_t *kSaverClass = L"StarfieldSaverWindow";
static volatile int g_running = 1;
static int g_preview = 0;
static DWORD g_startTick;
static POINT g_startCursor;
static int g_haveCursor;

static LRESULT CALLBACK saver_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_SETCURSOR:
        SetCursor(NULL);
        return TRUE;
    case WM_ERASEBKGND:
        return 1;
    case WM_KEYDOWN: case WM_SYSKEYDOWN:
    case WM_LBUTTONDOWN: case WM_RBUTTONDOWN: case WM_MBUTTONDOWN:
        if (!g_preview) g_running = 0;
        return 0;
    case WM_MOUSEMOVE:
        if (!g_preview) {
            POINT p; GetCursorPos(&p);
            if (!g_haveCursor) { g_startCursor = p; g_haveCursor = 1; }
            else if (GetTickCount() - g_startTick > GRACE_MS &&
                     (abs(p.x - g_startCursor.x) > MOUSE_SLOP || abs(p.y - g_startCursor.y) > MOUSE_SLOP))
                g_running = 0;
        }
        return 0;
    case WM_ACTIVATEAPP:
        if (!wp && !g_preview && GetTickCount() - g_startTick > GRACE_MS) g_running = 0;
        return 0;
    case WM_SYSCOMMAND:
        if ((wp & 0xFFF0) == SC_SCREENSAVE || (wp & 0xFFF0) == SC_MONITORPOWER) return 0;
        break;
    case WM_CLOSE:
        g_running = 0;
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

static float now_seconds(void) {
    static LARGE_INTEGER freq;
    LARGE_INTEGER t;
    if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t);
    return (float)((double)t.QuadPart / (double)freq.QuadPart);
}

static int run_saver(HINSTANCE inst, HWND previewParent) {
    Settings cfg = load_settings();
    g_preview = previewParent != NULL;

    WNDCLASSW wc = { 0 };
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
        savers[count] = (Saver *)calloc(1, sizeof(Saver));
        saver_init(savers[count++], h, cfg.stars < PREVIEW_STARS ? cfg.stars : PREVIEW_STARS);
    } else {
        EnumDisplayMonitors(NULL, NULL, monitor_cb, 0);
        for (int i = 0; i < g_monCount; i++) {
            RECT r = g_monRects[i];
            HWND h = CreateWindowExW(WS_EX_TOPMOST, kSaverClass, L"Starfield", WS_POPUP | WS_VISIBLE,
                                     r.left, r.top, r.right - r.left, r.bottom - r.top, NULL, NULL, inst, NULL);
            if (!h) continue;
            savers[count] = (Saver *)calloc(1, sizeof(Saver));
            saver_init(savers[count++], h, cfg.stars);
        }
        if (!count) return 1;
        ShowCursor(FALSE);
    }
    g_startTick = GetTickCount();

    float last = now_seconds();
    while (g_running) {
        MSG m;
        while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) {
            if (m.message == WM_QUIT) g_running = 0;
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
        if (g_preview && !IsWindow(previewParent)) break;

        float t = now_seconds();
        float dt = (t - last) * 60.0f;            /* time-based: same speed at any refresh rate */
        last = t;
        if (dt > 4.0f) dt = 4.0f;

        for (int i = 0; i < count; i++) {
            saver_step(savers[i], dt, &cfg);
            saver_draw(savers[i], &cfg);
            saver_present(savers[i]);
        }
        /* Block until the next display refresh; fall back to a short sleep if DWM is unavailable. */
        if (FAILED(DwmFlush())) Sleep(8);
    }

    for (int i = 0; i < count; i++) {
        saver_free(savers[i]);
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

    WNDCLASSW wc = { 0 };
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
