import UIKit
import Social
import UniformTypeIdentifiers

/**
 * iOS Share Extension handling fast one-shot clipboard and file sharing (PROTO-DC-V2.0 §14.3, FR-03C)
 * Designed with Swift native URLSession to strictly respect Jetsam RAM quota (< 30 MB peak RAM).
 *
 * completeRequest MUST be called only after the send finishes: once it is called iOS may
 * terminate the extension, killing any in-flight request.
 */
class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProviders = extensionItem.attachments,
              let provider = itemProviders.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
              }) else {
            finish()
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, _) in
            guard let self = self else { return }
            guard let text = item as? String else {
                self.finish()
                return
            }
            self.sendClipboardToDesktop(text: text) { _ in
                self.finish()
            }
        }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    /// Calls `completion` exactly once, after the request has finished (or failed).
    private func sendClipboardToDesktop(text: String, completion: @escaping (Bool) -> Void) {
        // Reads trusted desktop endpoints from App Group: group.com.dropclip.shared
        let userDefaults = UserDefaults(suiteName: "group.com.dropclip.shared")
        guard userDefaults?.string(forKey: "last_active_desktop_ip") != nil else {
            completion(false)
            return
        }

        // TODO(T3.2): POST /api/v1/clipboard (PROTO-DC-V2.0 §9.4) over mTLS with the shared
        // SecIdentity, and call completion from the URLSession task's completion handler.
        completion(false)
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}
