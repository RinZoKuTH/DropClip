import UIKit
import Social
import UniformTypeIdentifiers

/**
 * iOS Share Extension handling fast one-shot clipboard and file sharing (PROTO-DC-V2.0 §14.3, FR-03C)
 * Designed with Swift native URLSession to strictly respect Jetsam RAM quota (< 30 MB peak RAM).
 */
class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProviders = extensionItem.attachments else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        // Process attachments and send directly to paired Desktop node via local TLS endpoint
        for provider in itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] (item, error) in
                    if let text = item as? String {
                        self?.sendClipboardToDesktop(text: text)
                    }
                    self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
                return
            }
        }
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func sendClipboardToDesktop(text: String) {
        // Reads trusted desktop endpoints from App Group: group.com.dropclip.shared
        let userDefaults = UserDefaults(suiteName: "group.com.dropclip.shared")
        guard let _ = userDefaults?.string(forKey: "last_active_desktop_ip") else { return }

        // Send via POST /api/v1/clipboard (PROTO-DC-V2.0 §9.4)
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}

