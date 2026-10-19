//
//  ShareViewController.swift
//  My Videos Share
//

import Cocoa

/// "Share → My Videos": hands the shared link to the app, which queues the download.
/// There's no UI — the app itself shows progress — so the request completes immediately.
final class ShareViewController: NSViewController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async { self.handOff(url?.absoluteString) }
            }
        } else if let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                let link = text?.split(whereSeparator: \.isWhitespace).first.map(String.init)
                DispatchQueue.main.async { self.handOff(link) }
            }
        } else {
            handOff(nil)
        }
    }

    private func handOff(_ link: String?) {
        // Encode everything but unreserved characters so "&list=…" survives the trip.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let link, link.hasPrefix("http"),
              let encoded = link.addingPercentEncoding(withAllowedCharacters: unreserved),
              let url = URL(string: "myvideos://download?url=\(encoded)") else {
            extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            return
        }
        NSWorkspace.shared.open(url)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
