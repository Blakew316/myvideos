//
//  MediaSniffer.swift
//  My Videos
//
//  For sites yt-dlp doesn't know: finds video a page publishes openly, first in its
//  HTML (<video>, <source>, og:video, JSON-LD, links to media files) and then by loading
//  it, muted and unseen, the way a browser would. It reads only the page itself — not
//  players embedded from other sites — and stops at copy protection (DRM).
//

import Foundation
import WebKit

nonisolated struct SniffedPage: Sendable, Equatable {
    var title: String
    var imageURL: URL?
    /// Best first: streaming manifests, then files.
    var mediaURLs: [URL]
    var isProtected = false
}

@MainActor
enum MediaSniffer {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.0 Safari/605.1.15"

    private static var cache: [String: (page: SniffedPage, at: Date)] = [:]

    /// Looks for openly published media on a web page. Results are kept briefly so a
    /// preview and the download that follows don't load the page twice.
    static func sniff(_ page: URL) async -> SniffedPage? {
        guard page.scheme == "http" || page.scheme == "https" else { return nil }
        if let hit = cache[page.absoluteString], Date().timeIntervalSince(hit.at) < 600 { return hit.page }
        var found = await fromHTML(page)
        if found?.mediaURLs.isEmpty ?? true, let rendered = await fromRenderedPage(page) {
            found = SniffedPage(title: rendered.title.isEmpty ? found?.title ?? "" : rendered.title,
                                imageURL: rendered.imageURL ?? found?.imageURL,
                                mediaURLs: rendered.mediaURLs, isProtected: rendered.isProtected)
        }
        if let found { cache[page.absoluteString] = (found, Date()) }
        return found
    }

    /// What a sniffed page looks like as a preview.
    static func info(for page: SniffedPage, url: String) -> MediaInfo {
        MediaInfo(id: url, title: page.title.isEmpty ? (URL(string: url)?.host() ?? "Video") : page.title,
                  uploader: URL(string: url)?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: ""),
                  duration: nil, thumbnailURL: page.imageURL, webpageURL: url, site: "Web page",
                  isPlaylist: false, playlistCount: nil, track: nil, artist: nil, album: nil,
                  isLive: false, channelURL: nil)
    }

    // MARK: - HTML

    private static func fromHTML(_ page: URL) async -> SniffedPage? {
        var request = URLRequest(url: page, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return nil }
        // A link straight to a media file.
        if let type = http.mimeType, type.hasPrefix("video/") || type.hasPrefix("audio/") || isManifestType(type) {
            return SniffedPage(title: page.deletingPathExtension().lastPathComponent, mediaURLs: [page])
        }
        let html = String(decoding: data.prefix(3_000_000), as: UTF8.self)
        return parse(html: html, base: http.url ?? page)
    }

    /// Pulls title, artwork and media links out of a page's HTML.
    nonisolated static func parse(html: String, base: URL) -> SniffedPage {
        func all(_ pattern: String) -> [String] {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
            return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
                Range($0.range(at: 1), in: html).map { String(html[$0]) }
            }
        }
        var candidates: [String] = []
        candidates += all(#"<(?:video|audio|source)\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#)
        candidates += all(#"<meta[^>]+(?:property|name)\s*=\s*["'](?:og:video(?::secure_url|:url)?|twitter:player:stream)["'][^>]*content\s*=\s*["']([^"']+)["']"#)
        candidates += all(#"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']og:video(?::secure_url|:url)?["']"#)
        candidates += all(#""contentUrl"\s*:\s*"([^"]+)""#)
        candidates += all(#"(https?:(?:\\?/){2}[^\s"'<>]+?\.(?:m3u8|mpd|mp4|m4v|mov|webm|m4a|mp3)(?:\?[^\s"'<>]*)?)"#)

        let title = decode(all(#"<meta[^>]+property\s*=\s*["']og:title["'][^>]*content\s*=\s*["']([^"']+)["']"#).first
            ?? all(#"<title[^>]*>([^<]+)</title>"#).first ?? base.host() ?? "Video")
        let image = all(#"<meta[^>]+property\s*=\s*["']og:image(?::secure_url)?["'][^>]*content\s*=\s*["']([^"']+)["']"#).first
            .flatMap { URL(string: decode($0), relativeTo: base)?.absoluteURL }
        return SniffedPage(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                           imageURL: image, mediaURLs: rank(candidates, base: base))
    }

    // MARK: - Rendered page

    /// Media the page loads once its scripts run. Copy protection is noticed when the
    /// page asks for a DRM key system.
    private static func fromRenderedPage(_ page: URL) async -> SniffedPage? {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(WKUserScript(
            source: watchScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: configuration)
        webView.customUserAgent = userAgent
        webView.load(URLRequest(url: page, timeoutInterval: 20))
        defer {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)  // stop any playback
        }

        var latest: SniffedPage?
        var previous: [URL] = []
        for _ in 0..<15 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return nil }
            guard let json = try? await webView.evaluateJavaScript(collectScript) as? String,
                  let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { continue }
            let base = webView.url ?? page
            let found = SniffedPage(
                title: (object["title"] as? String).map(decode) ?? base.host() ?? "Video",
                imageURL: (object["image"] as? String).flatMap { URL(string: $0, relativeTo: base)?.absoluteURL },
                mediaURLs: rank(object["urls"] as? [String] ?? [], base: base),
                isProtected: object["drm"] as? Bool ?? false)
            latest = found
            if found.isProtected { return found }
            if found.mediaURLs.contains(where: isManifest) { return found }
            // A file only: wait until the page stops adding media (a teaser can come first).
            if !found.mediaURLs.isEmpty, found.mediaURLs == previous { return found }
            previous = found.mediaURLs
        }
        return latest
    }

    /// Runs before the page's own scripts: keeps it silent and notes any DRM request.
    private static let watchScript = """
    (() => {
      window.__mvDRM = false;
      const request = navigator.requestMediaKeySystemAccess;
      if (request) {
        navigator.requestMediaKeySystemAccess = function() { window.__mvDRM = true; return request.apply(navigator, arguments); };
      }
      if (window.WebKitMediaKeys) {
        const Keys = window.WebKitMediaKeys;
        window.WebKitMediaKeys = function() { window.__mvDRM = true; return new Keys(...arguments); };
        window.WebKitMediaKeys.isTypeSupported = Keys.isTypeSupported;
      }
      const play = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() { this.muted = true; return play.apply(this, arguments); };
    })();
    """

    private static let collectScript = """
    (() => {
      const urls = new Set();
      const add = u => { if (u && !u.startsWith('blob:') && !u.startsWith('data:')) urls.add(u); };
      document.querySelectorAll('video, audio, source').forEach(e => { add(e.currentSrc); add(e.src); e.muted = true; });
      performance.getEntriesByType('resource').forEach(r => {
        if (/\\.(m3u8|mpd|mp4|m4v|mov|webm|m4a|mp3)(\\?|$)/i.test(r.name)) add(r.name);
      });
      const og = document.querySelector('meta[property="og:image"]');
      const ogTitle = document.querySelector('meta[property="og:title"]');
      return JSON.stringify({ urls: [...urls], drm: !!window.__mvDRM,
                              title: (ogTitle && ogTitle.content) || document.title, image: og ? og.content : '' });
    })()
    """

    // MARK: - Helpers

    /// Resolves, de-duplicates, drops ads and puts manifests first.
    nonisolated static func rank(_ raw: [String], base: URL) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for candidate in raw {
            let cleaned = decode(candidate.replacingOccurrences(of: "\\/", with: "/"))
            guard let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
                  url.scheme == "http" || url.scheme == "https",
                  !isAd(url), seen.insert(url.absoluteString).inserted else { continue }
            urls.append(url)
        }
        return urls.filter(isManifest) + urls.filter { !isManifest($0) }
    }

    nonisolated static func isManifest(_ url: URL) -> Bool {
        ["m3u8", "mpd"].contains(url.pathExtension.lowercased())
    }

    nonisolated private static func isManifestType(_ type: String) -> Bool {
        type.contains("mpegurl") || type.contains("dash+xml")
    }

    nonisolated private static func isAd(_ url: URL) -> Bool {
        let text = url.absoluteString.lowercased()
        return ["doubleclick", "googlesyndication", "/ads/", "adserver", "preroll", "/vast", "imasdk"].contains { text.contains($0) }
    }

    nonisolated private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
