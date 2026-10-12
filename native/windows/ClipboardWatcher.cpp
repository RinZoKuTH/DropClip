#include <windows.h>
#include <iostream>

/**
 * Windows Native Clipboard Watcher using Win32 Event-Driven Listener (PROTO-DC-V2.0 §14.1, FR-03A)
 */
class WindowsClipboardWatcher {
private:
    HWND hwndMessage;
    bool isListening;

    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
        if (msg == WM_CLIPBOARDUPDATE) {
            // Event-driven clipboard update received
            // Check for excluded/sensitive format flags (FR-05)
            UINT cfExclude = RegisterClipboardFormatA("ExcludeClipboardContentFromMonitorProcessing");
            if (cfExclude != 0 && IsClipboardFormatAvailable(cfExclude)) {
                // Concealed content - skip processing
                return 0;
            }
            // Notify Flutter layer through Platform Channel
            return 0;
        }
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }

public:
    WindowsClipboardWatcher() : hwndMessage(NULL), isListening(false) {}

    bool Start() {
        WNDCLASSA wc = {0};
        wc.lpfnWndProc = WndProc;
        wc.hInstance = GetModuleHandle(NULL);
        wc.lpszClassName = "DropClipWatcherClass";
        RegisterClassA(&wc);

        hwndMessage = CreateWindowA("DropClipWatcherClass", "DropClipWatcher", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, NULL, NULL);
        if (!hwndMessage) return false;

        if (AddClipboardFormatListener(hwndMessage)) {
            isListening = true;
            return true;
        }
        return false;
    }

    void Stop() {
        if (isListening && hwndMessage) {
            RemoveClipboardFormatListener(hwndMessage);
            DestroyWindow(hwndMessage);
            hwndMessage = NULL;
            isListening = false;
        }
    }

    ~WindowsClipboardWatcher() {
        Stop();
    }
};

