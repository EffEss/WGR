// WeatherGlance-Lite: minimal Win32 WebView2 host
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <wrl.h>
#include <string>
#include <thread>
#include <urlmon.h>
#include <shlwapi.h>
#include "WebView2.h"
#pragma comment(lib, "urlmon.lib")
using namespace Microsoft::WRL;

#define IDR_RADAR_HTML  200
#define IDR_STATES_JSON 201
#define WM_RADAR_DONE (WM_USER + 1)
struct DlResult { std::wstring region; std::wstring file; std::wstring error; };

static HWND g_hwnd = nullptr;
static ComPtr<ICoreWebView2Controller> g_ctrl;
static ComPtr<ICoreWebView2> g_webview;
static ComPtr<ICoreWebView2Environment> g_env;

static IStream* LoadEmbeddedResource(int id) {
    HRSRC hRes = FindResourceW(nullptr, MAKEINTRESOURCEW(id), MAKEINTRESOURCEW(10));
    if (!hRes) return nullptr;
    HGLOBAL hData = LoadResource(nullptr, hRes);
    if (!hData) return nullptr;
    return SHCreateMemStream((const BYTE*)LockResource(hData), SizeofResource(nullptr, hRes));
}

static std::wstring GetExeDir() {
    wchar_t buf[MAX_PATH]; GetModuleFileNameW(nullptr, buf, MAX_PATH);
    std::wstring p(buf); return p.substr(0, p.find_last_of(L"\\/") + 1);
}
static std::wstring GetRadarDir() {
    auto d = GetExeDir() + L"radar";
    CreateDirectoryW(d.c_str(), nullptr);
    return d;
}
static std::wstring GetCacheDir() {
    auto d = GetExeDir() + L"Cache";
    CreateDirectoryW(d.c_str(), nullptr);
    return d;
}
static void ResizeWebView() {
    if (!g_ctrl) return;
    RECT rc; GetClientRect(g_hwnd, &rc); g_ctrl->put_Bounds(rc);
}

static void DownloadRadarGif(std::wstring url, std::wstring region) {
    auto dir = GetRadarDir();
    auto dest = dir + L"\\" + region + L".gif";
    auto* r = new DlResult();
    r->region = region;
    HRESULT hr = URLDownloadToFileW(nullptr, url.c_str(), dest.c_str(), 0, nullptr);
    if (SUCCEEDED(hr)) {
        WIN32_FILE_ATTRIBUTE_DATA fad;
        if (GetFileAttributesExW(dest.c_str(), GetFileExInfoStandard, &fad) && fad.nFileSizeLow > 5120) {
            r->file = region + L".gif";
        } else {
            r->error = L"Response too small";
            DeleteFileW(dest.c_str());
        }
    } else {
        r->error = L"Download failed";
    }
    PostMessage(g_hwnd, WM_RADAR_DONE, 0, (LPARAM)r);
}

static void CleanRadarCache() {
    auto dir = GetRadarDir();
    WIN32_FIND_DATAW fd;
    auto pat = dir + L"\\*.gif";
    HANDLE h = FindFirstFileW(pat.c_str(), &fd);
    if (h != INVALID_HANDLE_VALUE) {
        do { DeleteFileW((dir + L"\\" + fd.cFileName).c_str()); } while (FindNextFileW(h, &fd));
        FindClose(h);
    }
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_SIZE) { ResizeWebView(); return 0; }
    if (msg == WM_DESTROY) { CleanRadarCache(); PostQuitMessage(0); return 0; }
    if (msg == WM_RADAR_DONE) {
        auto* r = (DlResult*)lp;
        if (g_webview) {
            wchar_t json[512];
            if (r->error.empty()) {
                swprintf_s(json, L"{\"type\":\"radarReady\",\"region\":\"%s\",\"file\":\"%s\"}",
                    r->region.c_str(), r->file.c_str());
            } else {
                swprintf_s(json, L"{\"type\":\"radarError\",\"region\":\"%s\",\"error\":\"%s\"}",
                    r->region.c_str(), r->error.c_str());
            }
            g_webview->PostWebMessageAsJson(json);
        }
        delete r;
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static void InitWebView() {
    auto udd = GetCacheDir();
    // Reduce cache bloat by disabling unused Chromium/Edge features
    SetEnvironmentVariableW(L"WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
        L"--disable-features="
            L"msSmartScreenProtection,"
            L"msEdgeJourneys,"
            L"msParcelTracking,"
            L"msEdgeShoppingUI,"
            L"msEdgeDevToolsWelcomeExperience,"
            L"msPersistentOriginTrials,"
            L"OptimizationHints,"
            L"EdgeDiscoverEnabled,"
            L"InterestFeedContentSuggestions,"
            L"BrowsingTopics,"
            L"SharedDictionaries "
        L"--no-first-run "
        L"--disable-component-update "
        L"--disable-crash-reporter "
        L"--disable-client-side-phishing-detection "
        L"--disable-sync "
        L"--disable-domain-reliability "
        L"--disable-gpu-shader-disk-cache "
        L"--disable-gpu "
        L"--disk-cache-size=1048576");
    CreateCoreWebView2EnvironmentWithOptions(nullptr, udd.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [](HRESULT hr, ICoreWebView2Environment* env) -> HRESULT {
            if (FAILED(hr)) return hr;
            g_env = env;
            env->CreateCoreWebView2Controller(g_hwnd,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [](HRESULT hr, ICoreWebView2Controller* ctrl) -> HRESULT {
                    if (FAILED(hr)) return hr;
                    g_ctrl = ctrl;
                    g_ctrl->get_CoreWebView2(&g_webview);
                    ResizeWebView();
                    // Serve radar GIF cache from disk
                    ComPtr<ICoreWebView2_3> wv3;
                    g_webview.As(&wv3);
                    if (wv3) {
                        auto rd = GetRadarDir();
                        wv3->SetVirtualHostNameToFolderMapping(
                            L"radar-cache.local", rd.c_str(),
                            COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
                    }
                    // Serve embedded assets via WebResourceRequested
                    g_webview->AddWebResourceRequestedFilter(
                        L"https://app.local/*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
                    g_webview->add_WebResourceRequested(
                        Callback<ICoreWebView2WebResourceRequestedEventHandler>(
                            [](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
                            ComPtr<ICoreWebView2WebResourceRequest> req;
                            args->get_Request(&req);
                            LPWSTR uri = nullptr;
                            req->get_Uri(&uri);
                            if (!uri) return S_OK;
                            std::wstring url(uri);
                            CoTaskMemFree(uri);
                            int resId = 0;
                            const wchar_t* ct = nullptr;
                            if (url.find(L"radar-map.html") != std::wstring::npos) {
                                resId = IDR_RADAR_HTML; ct = L"text/html; charset=utf-8";
                            } else if (url.find(L"us-states.geo.json") != std::wstring::npos) {
                                resId = IDR_STATES_JSON; ct = L"application/json";
                            }
                            if (resId) {
                                IStream* stream = LoadEmbeddedResource(resId);
                                if (stream) {
                                    ComPtr<ICoreWebView2WebResourceResponse> resp;
                                    wchar_t hdr[128];
                                    swprintf_s(hdr, L"Content-Type: %s\r\nAccess-Control-Allow-Origin: *", ct);
                                    g_env->CreateWebResourceResponse(stream, 200, L"OK", hdr, &resp);
                                    args->put_Response(resp.Get());
                                    stream->Release();
                                }
                            }
                            return S_OK;
                        }).Get(), nullptr);
                    // Listen for download requests from JS
                    g_webview->add_WebMessageReceived(
                        Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                            [](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                            LPWSTR msgRaw = nullptr;
                            args->TryGetWebMessageAsString(&msgRaw);
                            if (msgRaw) {
                                std::wstring m(msgRaw);
                                CoTaskMemFree(msgRaw);
                                // Parse: "DOWNLOAD|region|url"
                                auto p1 = m.find(L'|');
                                if (p1 != std::wstring::npos && m.substr(0, p1) == L"DOWNLOAD") {
                                    auto p2 = m.find(L'|', p1 + 1);
                                    if (p2 != std::wstring::npos) {
                                        auto region = m.substr(p1 + 1, p2 - p1 - 1);
                                        auto url = m.substr(p2 + 1);
                                        std::thread(DownloadRadarGif, url, region).detach();
                                    }
                                } else if (p1 != std::wstring::npos && m.substr(0, p1) == L"CLEARCACHE") {
                                    CleanRadarCache();
                                    if (g_webview) g_webview->PostWebMessageAsJson(L"{\"type\":\"cacheCleared\"}");
                                } else if (p1 != std::wstring::npos && m.substr(0, p1) == L"CACHESIZE") {
                                    auto dir = GetRadarDir();
                                    WIN32_FIND_DATAW fd;
                                    auto pat = dir + L"\\*.gif";
                                    HANDLE h = FindFirstFileW(pat.c_str(), &fd);
                                    ULONGLONG total = 0; int count = 0;
                                    if (h != INVALID_HANDLE_VALUE) {
                                        do { total += ((ULONGLONG)fd.nFileSizeHigh << 32) | fd.nFileSizeLow; count++; } while (FindNextFileW(h, &fd));
                                        FindClose(h);
                                    }
                                    wchar_t json[128];
                                    swprintf_s(json, L"{\"type\":\"cacheSize\",\"bytes\":%llu,\"count\":%d}", total, count);
                                    if (g_webview) g_webview->PostWebMessageAsJson(json);
                                }
                            }
                            return S_OK;
                        }).Get(), nullptr);
                    ComPtr<ICoreWebView2Settings> s;
                    g_webview->get_Settings(&s);
                    s->put_IsStatusBarEnabled(FALSE);
                    s->put_AreDefaultContextMenusEnabled(FALSE);
                    s->put_AreDevToolsEnabled(TRUE);
                    ComPtr<ICoreWebView2Settings4> s4;
                    if (SUCCEEDED(s.As(&s4))) {
                        s4->put_IsPasswordAutosaveEnabled(FALSE);
                        s4->put_IsGeneralAutofillEnabled(FALSE);
                    }
                    ComPtr<ICoreWebView2Controller2> c2;
                    g_ctrl.As(&c2);
                    if (c2) {
                        COREWEBVIEW2_COLOR bg = { 255, 13, 17, 23 };
                        c2->put_DefaultBackgroundColor(bg);
                    }
                    g_webview->Navigate(L"https://app.local/radar-map.html");
                    return S_OK;
                }).Get());
            return S_OK;
        }).Get());
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, LPWSTR, int nShow) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = L"WeatherGlanceLite";
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = CreateSolidBrush(RGB(13, 17, 23));
    wc.hIcon = LoadIconW(hInst, MAKEINTRESOURCEW(101));
    RegisterClassW(&wc);
    g_hwnd = CreateWindowExW(0, L"WeatherGlanceLite", L"Drizzle",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 700, 620,
        nullptr, nullptr, hInst, nullptr);
    ShowWindow(g_hwnd, nShow);
    UpdateWindow(g_hwnd);
    InitWebView();
    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    CoUninitialize();
    return (int)msg.wParam;
}