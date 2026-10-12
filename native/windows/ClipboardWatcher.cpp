#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00  // Windows 10
#endif
#ifndef UNICODE
#define UNICODE
#endif
#include <windows.h>

#include <functional>
#include <utility>

/**
 * Windows Native Clipboard Watcher using Win32 Event-Driven Listener (PROTO-DC-V2.0 §14.1, FR-03A)
 *
 * Threading: Start()/Stop() MUST be called on a thread that pumps a Win32 message loop
 * (the Flutter Windows runner's platform thread does). The watcher itself never reads
 * clipboard content; it only reports "changed" + whether the change is concealed (§10.4).
 */
class WindowsClipboardWatcher {
public:
    // concealed == true → content MUST NOT be read or synced (NFR-S04).
    // sequence  == GetClipboardSequenceNumber() at the time of the change.
    using ChangeCallback = std::function<void(bool concealed, DWORD sequence)>;

    explicit WindowsClipboardWatcher(ChangeCallback onChange)
        : onChange_(std::move(onChange)),
          cfExclude_(RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing")),
          cfHistory_(RegisterClipboardFormatW(L"CanIncludeInClipboardHistory")),
          cfCloud_(RegisterClipboardFormatW(L"CanUploadToCloudClipboard")) {}

    WindowsClipboardWatcher(const WindowsClipboardWatcher&) = delete;
    WindowsClipboardWatcher& operator=(const WindowsClipboardWatcher&) = delete;

    ~WindowsClipboardWatcher() { Stop(); }

    bool Start() {
        if (hwnd_ != nullptr) return true;  // Already running

        WNDCLASSEXW wc = {};
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = &WindowsClipboardWatcher::WndProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.lpszClassName = kClassName;
        if (RegisterClassExW(&wc) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }

        // `this` is handed over through lpParam and stored in GWLP_USERDATA on WM_NCCREATE.
        hwnd_ = CreateWindowExW(0, kClassName, L"DropClipWatcher", 0, 0, 0, 0, 0,
                                HWND_MESSAGE, nullptr, wc.hInstance, this);
        if (hwnd_ == nullptr) return false;

        if (!AddClipboardFormatListener(hwnd_)) {
            DestroyWindow(hwnd_);
            hwnd_ = nullptr;
            return false;
        }
        return true;
    }

    void Stop() {
        if (hwnd_ == nullptr) return;
        RemoveClipboardFormatListener(hwnd_);
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }

    // Our own window; used by the writer side so that echo of our writes can be skipped.
    HWND Handle() const { return hwnd_; }

private:
    static constexpr const wchar_t* kClassName = L"DropClipWatcherClass";

    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
        if (msg == WM_NCCREATE) {
            auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                              reinterpret_cast<LONG_PTR>(create->lpCreateParams));
        }
        auto* self = reinterpret_cast<WindowsClipboardWatcher*>(
            GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        if (msg == WM_CLIPBOARDUPDATE && self != nullptr) {
            self->OnClipboardUpdate();
            return 0;
        }
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }

    void OnClipboardUpdate() {
        // Echo of our own write (we called OpenClipboard(hwnd_) + EmptyClipboard()).
        if (GetClipboardOwner() == hwnd_) return;
        if (onChange_) onChange_(IsConcealed(), GetClipboardSequenceNumber());
    }

    // PROTO §10.4 Windows markers. Presence of the exclude format, or a DWORD 0 in either
    // history/cloud format, means the source app (e.g. a password manager) marked it sensitive.
    bool IsConcealed() const {
        if (cfExclude_ != 0 && IsClipboardFormatAvailable(cfExclude_)) return true;

        const bool hasHistory = cfHistory_ != 0 && IsClipboardFormatAvailable(cfHistory_);
        const bool hasCloud = cfCloud_ != 0 && IsClipboardFormatAvailable(cfCloud_);
        if (!hasHistory && !hasCloud) return false;

        if (!OpenClipboardWithRetry()) return true;  // Fail closed: cannot verify → treat as concealed
        const bool concealed = (hasHistory && FormatIsZeroDword(cfHistory_)) ||
                               (hasCloud && FormatIsZeroDword(cfCloud_));
        CloseClipboard();
        return concealed;
    }

    static bool FormatIsZeroDword(UINT format) {
        HANDLE data = GetClipboardData(format);
        if (data == nullptr || GlobalSize(data) < sizeof(DWORD)) return false;
        const auto* value = static_cast<const DWORD*>(GlobalLock(data));
        if (value == nullptr) return false;
        const bool isZero = (*value == 0);
        GlobalUnlock(data);
        return isZero;
    }

    // CLIPBOARD_LOCK_RETRY (§16): 3 attempts with 50 / 100 / 200 ms backoff.
    bool OpenClipboardWithRetry() const {
        const DWORD delaysMs[] = {50, 100, 200};
        for (DWORD delay : delaysMs) {
            if (OpenClipboard(hwnd_)) return true;
            Sleep(delay);
        }
        return OpenClipboard(hwnd_) != FALSE;
    }

    ChangeCallback onChange_;
    HWND hwnd_ = nullptr;
    const UINT cfExclude_;
    const UINT cfHistory_;
    const UINT cfCloud_;
};
