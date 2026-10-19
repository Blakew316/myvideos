//
//  SystemIntegration.swift
//  My Videos
//

import AppKit
import SwiftUI
import WebKit

// MARK: - Dock progress

/// Draws a Finder-style progress bar over the Dock icon and badges the queue size.
final class DockProgress {
    static let shared = DockProgress()

    private var hostingView: NSHostingView<DockTileView>?
    private var lastDrawn: Double = -1

    func update(job: DownloadJob?, badgeCount: Int) {
        let tile = NSApp.dockTile
        tile.badgeLabel = badgeCount > 1 ? "\(badgeCount)" : nil

        guard let job else {
            if hostingView != nil {
                tile.contentView = nil
                hostingView = nil
                lastDrawn = -1
                tile.display()
            }
            return
        }
        let progress = job.progressIsIndeterminate ? nil : job.progress
        let rounded = progress.map { ($0 * 100).rounded() / 100 } ?? -2
        guard rounded != lastDrawn || hostingView == nil else { return }
        lastDrawn = rounded

        let view = DockTileView(progress: progress)
        if let hostingView {
            hostingView.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: tile.size)
            tile.contentView = host
            hostingView = host
        }
        tile.display()
    }
}

struct DockTileView: View {
    var progress: Double?

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.55))
                Capsule()
                    .fill(.white)
                    .padding(2.5)
                    .frame(width: max(14, 104 * (progress ?? 0.12)))
            }
            .frame(width: 104, height: 14)
            .padding(.bottom, 14)
        }
        .frame(width: 128, height: 128)
    }
}

// MARK: - Built-in sign-in

/// Sign-ins made in My Videos' own browser window live in WebKit's persistent store.
/// Before each download they're exported as a private cookies.txt for yt-dlp.
enum SignInSession {
    static var cookieFile: URL { HistoryStore.supportDirectory.appendingPathComponent("cookies.txt") }

    static var dataStore: WKWebsiteDataStore { .default() }

    /// Safari's user agent: Google refuses sign-in from agents it doesn't recognize.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    static func exportCookies() async -> URL? {
        let cookies = await dataStore.httpCookieStore.allCookies()
        guard !cookies.isEmpty else { return nil }
        var lines = ["# Netscape HTTP Cookie File", "# Exported by My Videos — do not share.", ""]
        for cookie in cookies {
            let domain = cookie.domain
            let includeSubdomains = domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let expiry = cookie.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            let name = cookie.name.replacingOccurrences(of: "\t", with: " ")
            let value = cookie.value.replacingOccurrences(of: "\t", with: " ")
            let httpOnly = cookie.isHTTPOnly ? "#HttpOnly_" : ""
            lines.append([httpOnly + domain, includeSubdomains, cookie.path,
                          cookie.isSecure ? "TRUE" : "FALSE", expiry, name, value].joined(separator: "\t"))
        }
        let file = cookieFile
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return file
        } catch {
            return nil
        }
    }

    /// Sites with an active sign-in, e.g. ["youtube.com", "vimeo.com"].
    static func signedInSites() async -> [String] {
        let cookies = await dataStore.httpCookieStore.allCookies()
        let authNames: Set<String> = ["SID", "SAPISID", "__Secure-3PSID", "LOGIN_INFO", "sessionid",
                                      "auth_token", "vuid", "c_user", "sid_tt", "auth-token"]
        let domains = cookies.filter { authNames.contains($0.name) }.map { cookie -> String in
            let parts = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".")
            return parts.suffix(2).joined(separator: ".")
        }
        return Array(Set(domains)).sorted()
    }

    static func signOutEverywhere() async {
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        try? FileManager.default.removeItem(at: cookieFile)
    }
}
