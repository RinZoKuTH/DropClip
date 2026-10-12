import Foundation
import AppKit

/// macOS Native Clipboard Watcher using Adaptive Polling (PROTO-DC-V2.0 §14.1, FR-03A)
public class ClipboardWatcher {
    private var lastChangeCount: Int
    private var isRunning: Bool = false
    private var timer: Timer?

    public init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    public func startWatching(onChanged: @escaping (Bool, [String: Data]) -> Void) {
        isRunning = true
        scheduleTimer(interval: 0.2, onChanged: onChanged) // 200ms active polling
    }

    public func stopWatching() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer(interval: TimeInterval, onChanged: @escaping (Bool, [String: Data]) -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            let currentCount = NSPasteboard.general.changeCount
            if currentCount != self.lastChangeCount {
                self.lastChangeCount = currentCount
                self.handleClipboardChange(onChanged: onChanged)
            }
        }
    }

    private func handleClipboardChange(onChanged: @escaping (Bool, [String: Data]) -> Void) {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []

        // FR-05 Sensitive filtering: check org.nspasteboard.ConcealedType
        let isConcealed = types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) ||
                          types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        if isConcealed {
            onChanged(true, [:]) // Do not read content for concealed data
            return
        }

        var items: [String: Data] = [:]
        if let text = pasteboard.string(forType: .string) {
            items["text/plain"] = text.data(using: .utf8)
        }
        if let pngData = pasteboard.data(forType: .png) {
            items["image/png"] = pngData
        } else if let tiffData = pasteboard.data(forType: .tiff) {
            items["image/tiff"] = tiffData
        }

        onChanged(false, items)
    }
}
