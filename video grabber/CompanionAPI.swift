//
//  CompanionAPI.swift
//  My Videos
//
//  Routes for the iPhone web app. Everything under /api and /media needs the pairing token.
//

import Foundation
import Observation

/// Pairing between the Mac and the iPhone app: a 6-digit code exchanged once for a token.
@Observable
final class CompanionPairing {
    static let shared = CompanionPairing()

    private(set) var code: String
    private(set) var token: String
    private var failedAttempts = 0
    private var lockedUntil = Date.distantPast

    private init() {
        let defaults = UserDefaults.standard
        code = defaults.string(forKey: "companionCode") ?? Self.newCode()
        token = defaults.string(forKey: "companionToken") ?? Self.newToken()
        save()
    }

    /// New code and token; every paired iPhone has to pair again.
    func reset() {
        code = Self.newCode()
        token = Self.newToken()
        failedAttempts = 0
        save()
    }

    enum Result { case paired(String), wrongCode, locked }

    func pair(with attempt: String) -> Result {
        guard Date() >= lockedUntil else { return .locked }
        let digits = attempt.filter(\.isNumber)
        if digits == code {
            failedAttempts = 0
            return .paired(token)
        }
        failedAttempts += 1
        // Slows guessing to a crawl: 5 tries, then a 5-minute lockout.
        if failedAttempts >= 5 {
            lockedUntil = Date().addingTimeInterval(300)
            failedAttempts = 0
        }
        return .wrongCode
    }

    func isValid(_ candidate: String?) -> Bool {
        guard let candidate, candidate.count == token.count else { return false }
        // Constant-time comparison.
        return zip(candidate.utf8, token.utf8).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func save() {
        UserDefaults.standard.set(code, forKey: "companionCode")
        UserDefaults.standard.set(token, forKey: "companionToken")
    }

    private static func newCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Turns requests into actions on the app model.
enum CompanionAPI {
    static var model: AppModel { AppModel.shared }
    static var pairing: CompanionPairing { CompanionPairing.shared }

    static func handle(_ request: HTTPRequest) async -> HTTPResponse {
        if request.method == "OPTIONS" { return HTTPResponse(status: 204) }
        let parts = request.path.split(separator: "/").map(String.init)

        // Public: the web app itself.
        if request.method == "GET" || request.method == "HEAD" {
            if let asset = staticAsset(for: request.path) { return asset }
        }
        if request.method == "POST", request.path == "/api/pair" {
            return pair(request)
        }

        // Everything else needs the token (header for fetch, query for <video src> and links).
        let bearer = request.headers["authorization"].map { $0.replacingOccurrences(of: "Bearer ", with: "") }
        guard pairing.isValid(bearer ?? request.query["t"]) else {
            return parts.first == "add" ? .html(addPage(title: "Not Connected",
                                                         message: "Open My Videos on your iPhone and connect to your Mac first.",
                                                         ok: false), status: 401)
                                        : .error(401, "Not paired")
        }
        CompanionServer.shared.noteSeen()

        let route = Route(method: request.method, parts: parts)
        if route.is("GET", "add") { return quickAdd(request) }
        if let p = route.match("GET", "media/:id/:index") { return media(id: p[0], index: Int(p[1]) ?? 0, request: request) }
        if route.is("GET", "api/status") { return .json(status()) }
        if route.is("GET", "api/state") { return .json(state()) }
        if route.is("GET", "api/preview") { return await preview(request.query["url"] ?? "") }
        if route.is("POST", "api/download") { return download(request.json) }
        if let p = route.match("POST", "api/jobs/:id/:action") { return jobAction(id: p[0], action: p[1]) }
        if route.is("POST", "api/queue/clear") { model.clearFinished(); return .json(state()) }
        if route.is("POST", "api/queue/pause-all") { model.pauseAll(); return .json(state()) }
        if route.is("POST", "api/queue/resume-all") { model.resumeAll(); return .json(state()) }
        if route.is("GET", "api/history") {
            return .json(["items": model.history.items.prefix(500).map { historyJSON($0) }])
        }
        if let p = route.match("DELETE", "api/history/:id") {
            guard let uuid = UUID(uuidString: p[0]) else { return .error(400, "Bad id") }
            model.history.remove(ids: [uuid])
            return .json(["ok": true])
        }
        if let p = route.match("POST", "api/history/:id/:action") {
            guard let item = UUID(uuidString: p[0]).flatMap(model.history.item(id:)) else { return .error(404, "Not found") }
            switch p[1] {
            case "upgrade": model.upgradeToBestQuality(item)
            case "music": model.addToMusic(item)
            default: return .error(400, "Unknown action")
            }
            return .json(["ok": true])
        }
        if route.is("GET", "api/subscriptions") {
            return .json(["items": model.subscriptions.items.map { subscriptionJSON($0) },
                          "checking": model.checkingSubscriptions.map(\.uuidString)])
        }
        if route.is("POST", "api/subscriptions/preview") { return await feedPreview(request.json["url"] as? String ?? "") }
        if route.is("POST", "api/subscriptions") { return await subscribe(request.json) }
        if let p = route.match("POST", "api/subscriptions/:id/:action") {
            return await subscriptionAction(id: p[0], action: p[1], body: request.json)
        }
        if let p = route.match("DELETE", "api/subscriptions/:id") {
            guard let uuid = UUID(uuidString: p[0]) else { return .error(400, "Bad id") }
            model.unsubscribe(uuid)
            return .json(["ok": true])
        }
        if route.is("GET", "api/settings") { return .json(settingsJSON()) }
        if route.is("POST", "api/settings") {
            applySettings(request.json)
            return .json(settingsJSON())
        }
        return .error(404, "Not found")
    }

    /// Matches "api/jobs/:id/:action"-style patterns against a request.
    private struct Route {
        let method: String
        let parts: [String]

        func match(_ method: String, _ pattern: String) -> [String]? {
            guard self.method == method else { return nil }
            let pattern = pattern.split(separator: "/").map(String.init)
            guard pattern.count == parts.count else { return nil }
            var captures: [String] = []
            for (expected, actual) in zip(pattern, parts) {
                if expected.hasPrefix(":") { captures.append(actual) }
                else if expected != actual { return nil }
            }
            return captures
        }

        func `is`(_ method: String, _ pattern: String) -> Bool { match(method, pattern) != nil }
    }

    // MARK: - Static files

    private static let assets: [String: (name: String, ext: String)] = [
        "/": ("companion", "html"),
        "/index.html": ("companion", "html"),
        "/app.js": ("companion", "js"),
        "/app.css": ("companion", "css"),
        "/manifest.webmanifest": ("companion-manifest", "json"),
        "/icon.png": ("companion-icon", "png"),
        "/touch-icon.png": ("companion-touch-icon", "png"),
    ]

    private static func staticAsset(for path: String) -> HTTPResponse? {
        guard let asset = assets[path],
              let url = Bundle.main.url(forResource: asset.name, withExtension: asset.ext)
                ?? Bundle.main.url(forResource: asset.name, withExtension: asset.ext, subdirectory: "Companion"),
              let data = try? Data(contentsOf: url) else { return nil }
        let type = path == "/manifest.webmanifest" ? "application/manifest+json" : HTTPResponse.mimeType(for: asset.ext)
        return HTTPResponse(status: 200, headers: ["Content-Type": type, "Cache-Control": "no-cache"], body: data)
    }

    // MARK: - Pairing & status

    private static func pair(_ request: HTTPRequest) -> HTTPResponse {
        switch pairing.pair(with: request.json["code"] as? String ?? "") {
        case .paired(let token):
            CompanionServer.shared.noteSeen()
            return .json(["token": token, "mac": AppModel.deviceName])
        case .wrongCode:
            return .error(401, "That code doesn’t match. Check My Videos on your Mac.")
        case .locked:
            return .error(429, "Too many tries. Wait a few minutes, then try again.")
        }
    }

    private static func status() -> [String: Any] {
        [
            "mac": AppModel.deviceName,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "ready": model.toolchain.isReady,
            "missingTools": model.toolchain.missingTools,
        ]
    }

    // MARK: - Queue

    private static func state() -> [String: Any] {
        [
            "jobs": model.jobs.map { jobJSON($0) },
            "pending": model.pendingCount,
            "paused": model.pausedCount,
        ]
    }

    private static func jobJSON(_ job: DownloadJob) -> [String: Any] {
        var music = ""
        switch job.musicState {
        case .evening: music = "Evening out volume…"
        case .findingLyrics: music = "Finding lyrics…"
        case .adding: music = "Adding to Apple Music…"
        case .added: music = "Added to Apple Music"
        case .failed(let message): music = message
        case .none: break
        }
        return [
            "id": job.id.uuidString,
            "title": job.displayTitle,
            "subtitle": job.subtitle,
            "phase": phaseName(job.phase),
            "progress": job.progress,
            "indeterminate": job.progressIsIndeterminate,
            "status": job.statusLine,
            "music": music,
            "thumbnail": job.info?.thumbnailURL?.absoluteString ?? "",
            "isAudio": job.options.isAudio,
            "url": job.url,
            "error": job.technicalError ?? "",
            "files": job.savedFiles.map(\.path),
        ]
    }

    private static func phaseName(_ phase: DownloadJob.Phase) -> String {
        switch phase {
        case .queued: return "queued"
        case .preparing: return "preparing"
        case .downloading: return "downloading"
        case .processing: return "processing"
        case .paused: return "paused"
        case .finished: return "finished"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        }
    }

    private static func jobAction(id: String, action: String) -> HTTPResponse {
        guard let job = model.jobs.first(where: { $0.id.uuidString == id }) else { return .error(404, "Not found") }
        switch action {
        case "pause": model.pause(job)
        case "resume": model.resume(job)
        case "cancel": model.cancel(job)
        case "retry": model.retry(job)
        case "remove": model.remove(job)
        default: return .error(400, "Unknown action")
        }
        return .json(state())
    }

    // MARK: - Downloading

    private static func preview(_ link: String) async -> HTTPResponse {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppModel.isWebLink(trimmed) else { return .error(400, "That doesn’t look like a link.") }
        switch await model.lookUp(trimmed) {
        case .loaded(let info):
            var json: [String: Any] = [
                "title": info.title,
                "uploader": info.uploader ?? "",
                "duration": info.duration ?? 0,
                "thumbnail": info.thumbnailURL?.absoluteString ?? "",
                "site": info.site ?? "",
                "isPlaylist": info.isPlaylist,
                "playlistCount": info.playlistCount ?? 0,
                "hasPlaylist": info.isPlaylist || (URLComponents(string: trimmed)?.queryItems?.contains { $0.name == "list" } ?? false),
                "channelURL": info.channelURL ?? "",
                "subscribed": info.channelURL.map(model.subscriptions.contains(url:)) ?? false,
            ]
            if let existing = model.existingDownload(link: trimmed, info: info) {
                json["existing"] = historyJSON(existing)
            }
            return .json(json)
        case .failed(let message):
            return .error(422, message)
        default:
            return .error(422, "Couldn’t load details for this link.")
        }
    }

    private static func download(_ body: [String: Any]) -> HTTPResponse {
        let link = (body["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppModel.isWebLink(link) else { return .error(400, "That doesn’t look like a link.") }
        var options = model.prefs.baseOptions
        if (body["format"] as? String) == "audio" {
            options.quality = .audio
        } else {
            let quality = (body["quality"] as? String).flatMap(DownloadQuality.init(rawValue:))
            options.quality = quality ?? (model.prefs.quality == .audio ? .best : model.prefs.quality)
            if options.quality == .audio { options.quality = .best }
        }
        options.downloadPlaylist = body["playlist"] as? Bool ?? false
        if let limit = body["playlistLimit"] as? Int { options.playlistLimit = limit }
        model.enqueue(url: link, options: options, info: nil, tags: MusicTags())
        return .json(state())
    }

    /// For the iOS share-sheet Shortcut and the Safari bookmark: /add?t=…&url=…[&format=audio]
    private static func quickAdd(_ request: HTTPRequest) -> HTTPResponse {
        let link = request.query["url"] ?? ""
        guard AppModel.isWebLink(link) else {
            return .html(addPage(title: "Nothing to Download", message: "That page doesn’t have a web link.", ok: false), status: 400)
        }
        let audio = request.query["format"] == "audio"
        model.downloadImmediately(link, audioOnly: audio ? true : nil, showQueue: false)
        return .html(addPage(title: audio ? "Downloading Audio" : "Downloading",
                             message: "Sent to My Videos on \(AppModel.deviceName).", ok: true))
    }

    private static func addPage(title: String, message: String, ok: Bool) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <title>\(title)</title>
        <style>
        :root{color-scheme:light dark}
        body{margin:0;min-height:100vh;display:grid;place-items:center;font:-apple-system-body;font-family:-apple-system,system-ui;
        background:#f2f2f7;color:#000;text-align:center}
        @media(prefers-color-scheme:dark){body{background:#000;color:#fff}.m{color:#98989d}}
        .i{font-size:56px;width:96px;height:96px;border-radius:50%;display:grid;place-items:center;margin:0 auto 18px;
        background:\(ok ? "#34c759" : "#ff9f0a");color:#fff}
        h1{font-size:28px;margin:0 0 8px}.m{color:#6e6e73;margin:0 32px 28px}
        button{font:inherit;font-weight:600;border:0;border-radius:14px;padding:14px 28px;background:#5e5ce6;color:#fff}
        </style></head><body><div>
        <div class="i">\(ok ? "✓" : "!")</div><h1>\(title)</h1><p class="m">\(message)</p>
        <button onclick="history.length>1?history.back():window.close()">Done</button>
        </div></body></html>
        """
    }

    // MARK: - Library

    private static func historyJSON(_ item: HistoryItem) -> [String: Any] {
        let files = item.fileURLs.enumerated().compactMap { index, url -> [String: Any]? in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ["index": index, "name": url.lastPathComponent, "ext": url.pathExtension.lowercased(),
                    "playable": ["mp4", "m4v", "mov", "m4a", "mp3", "wav", "aac"].contains(url.pathExtension.lowercased())]
        }
        return [
            "id": item.id.uuidString,
            "title": item.title,
            "uploader": item.uploader ?? "",
            "date": ISO8601DateFormatter().string(from: item.date),
            "isAudio": item.isAudio,
            "isPlaylist": item.isPlaylist,
            "duration": item.duration ?? 0,
            "bytes": item.byteCount ?? 0,
            "thumbnail": item.thumbnailURL?.absoluteString ?? "",
            "source": item.sourceURL,
            "path": item.fileURLs.first { FileManager.default.fileExists(atPath: $0.path) }?.path ?? "",
            "device": item.deviceName ?? "",
            "files": files,
            "canUpgrade": !item.isAudio && item.quality != .best,
        ]
    }

    /// Streams a downloaded file with HTTP Range support, which iOS needs to play video.
    private static func media(id: String, index: Int, request: HTTPRequest) -> HTTPResponse {
        guard let item = UUID(uuidString: id).flatMap(model.history.item(id:)),
              item.fileURLs.indices.contains(index) else { return .error(404, "Not found") }
        let url = item.fileURLs[index]
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.int64Value > 0 else { return .error(404, "File missing") }
        let total = size.int64Value
        var headers = ["Content-Type": HTTPResponse.mimeType(for: url.pathExtension),
                       "Accept-Ranges": "bytes",
                       "Cache-Control": "private, max-age=3600"]
        if request.query["download"] == "1" {
            let name = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "download"
            headers["Content-Disposition"] = "attachment; filename*=UTF-8''\(name)"
        }

        guard let rangeHeader = request.headers["range"], rangeHeader.hasPrefix("bytes=") else {
            return HTTPResponse(status: 200, headers: headers, file: (url, 0...(total - 1)))
        }
        let spec = rangeHeader.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let bounds = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        var start: Int64 = 0, end: Int64 = total - 1
        if bounds.count == 2 {
            if bounds[0].isEmpty, let suffix = Int64(bounds[1]) {        // "bytes=-500"
                start = max(total - suffix, 0)
            } else {
                start = Int64(bounds[0]) ?? 0
                if let e = Int64(bounds[1]) { end = min(e, total - 1) }
            }
        }
        guard start <= end, start < total else {
            return HTTPResponse(status: 416, headers: ["Content-Range": "bytes */\(total)"])
        }
        headers["Content-Range"] = "bytes \(start)-\(end)/\(total)"
        return HTTPResponse(status: 206, headers: headers, file: (url, start...end))
    }

    // MARK: - Subscriptions

    private static func subscriptionJSON(_ sub: Subscription) -> [String: Any] {
        [
            "id": sub.id.uuidString,
            "title": sub.title,
            "url": sub.url,
            "avatar": sub.avatarURL?.absoluteString ?? "",
            "format": sub.isAudio ? "audio" : sub.quality.rawValue,
            "addToMusic": sub.addToMusic,
            "enabled": sub.isEnabled,
            "unseen": sub.unseenCount,
            "lastChecked": sub.lastChecked.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "error": sub.lastError ?? "",
            "downloadedCount": sub.downloadedIDs.count,
            "recent": sub.recent.map { entry in
                [
                    "id": entry.id,
                    "title": entry.title,
                    "url": entry.url,
                    "thumbnail": entry.thumbnailURL?.absoluteString ?? "",
                    "duration": entry.duration ?? 0,
                    "state": sub.downloadedIDs.contains(entry.id) ? "downloaded"
                        : (model.jobs.contains { $0.feedEntryID == entry.id && !$0.isDone } ? "downloading" : "available"),
                ] as [String: Any]
            },
        ]
    }

    private static func feedPreview(_ link: String) async -> HTTPResponse {
        guard AppModel.isWebLink(link) else { return .error(400, "Paste a link that starts with https://") }
        switch await model.fetchFeed(link) {
        case .success(let feed):
            return .json([
                "title": feed.title,
                "avatar": feed.avatarURL?.absoluteString ?? "",
                "latest": feed.entries.first?.title ?? "",
                "thumbnails": feed.entries.prefix(4).map { $0.thumbnailURL?.absoluteString ?? "" },
                "subscribed": model.subscriptions.contains(url: link),
            ])
        case .failure(let message):
            return .error(422, message)
        }
    }

    private static func subscribe(_ body: [String: Any]) async -> HTTPResponse {
        let link = (body["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppModel.isWebLink(link) else { return .error(400, "Paste a link that starts with https://") }
        guard !model.subscriptions.contains(url: link) else { return .error(409, "You’re already subscribed.") }
        switch await model.fetchFeed(link) {
        case .success(let feed):
            let isAudio = (body["format"] as? String) == "audio"
            let quality = (body["format"] as? String).flatMap(DownloadQuality.init(rawValue:)) ?? .best
            model.subscribe(link: link, feed: feed, isAudio: isAudio, quality: isAudio ? .best : quality,
                            addToMusic: body["addToMusic"] as? Bool ?? model.prefs.addToMusic,
                            downloadLatest: body["latest"] as? Int ?? 0)
            return .json(["items": model.subscriptions.items.map { subscriptionJSON($0) }])
        case .failure(let message):
            return .error(422, message)
        }
    }

    private static func subscriptionAction(id: String, action: String, body: [String: Any]) async -> HTTPResponse {
        guard let uuid = UUID(uuidString: id), let sub = model.subscriptions.subscription(id: uuid) else {
            return .error(404, "Not found")
        }
        switch action {
        case "check":
            await model.checkSubscription(uuid)
        case "enabled":
            model.subscriptions.updateChoices(uuid) { $0.isEnabled = body["value"] as? Bool ?? true }
        case "format":
            let value = body["value"] as? String ?? "best"
            model.subscriptions.updateChoices(uuid) {
                $0.isAudio = value == "audio"
                if let q = DownloadQuality(rawValue: value), q != .audio { $0.quality = q }
            }
        case "music":
            model.subscriptions.updateChoices(uuid) { $0.addToMusic = body["value"] as? Bool ?? true }
        case "viewed":
            model.markViewed(uuid)
        case "download":
            guard let entry = sub.recent.first(where: { $0.id == body["entry"] as? String }) else {
                return .error(404, "Upload not found")
            }
            model.download(entry, from: sub)
        default:
            return .error(400, "Unknown action")
        }
        return .json(["item": model.subscriptions.subscription(id: uuid).map { subscriptionJSON($0) } ?? [:]])
    }

    // MARK: - Settings

    private static func settingsJSON() -> [String: Any] {
        let p = model.prefs
        return [
            "mac": AppModel.deviceName,
            "quality": p.quality.rawValue,
            "audioFormat": p.audioFormat.rawValue,
            "addToMusic": p.addToMusic,
            "fetchLyrics": p.fetchLyrics,
            "normalizeVolume": p.normalizeVolume,
            "embedArtwork": p.embedArtwork,
            "sponsorBlock": p.sponsorBlock.rawValue,
            "subtitles": p.subtitles.rawValue,
            "qualities": DownloadQuality.allCases.filter { $0 != .audio }.map(\.rawValue),
            "audioFormats": AudioFormat.allCases.map { ["id": $0.rawValue, "name": $0.displayName] },
            "sponsorModes": SponsorBlockMode.allCases.map { ["id": $0.rawValue, "name": $0.displayName] },
            "subtitleModes": SubtitleMode.allCases.map { ["id": $0.rawValue, "name": $0.displayName] },
        ]
    }

    private static func applySettings(_ body: [String: Any]) {
        let p = model.prefs
        if let v = (body["quality"] as? String).flatMap(DownloadQuality.init(rawValue:)) { p.quality = v }
        if let v = (body["audioFormat"] as? String).flatMap(AudioFormat.init(rawValue:)) { p.audioFormat = v }
        if let v = body["addToMusic"] as? Bool { p.addToMusic = v }
        if let v = body["fetchLyrics"] as? Bool { p.fetchLyrics = v }
        if let v = body["normalizeVolume"] as? Bool { p.normalizeVolume = v }
        if let v = body["embedArtwork"] as? Bool { p.embedArtwork = v }
        if let v = (body["sponsorBlock"] as? String).flatMap(SponsorBlockMode.init(rawValue:)) { p.sponsorBlock = v }
        if let v = (body["subtitles"] as? String).flatMap(SubtitleMode.init(rawValue:)) { p.subtitles = v }
    }
}
