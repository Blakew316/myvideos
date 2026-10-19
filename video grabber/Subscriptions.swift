//
//  Subscriptions.swift
//  My Videos
//

import Foundation
import Observation

/// One upload in a channel or playlist feed.
nonisolated struct FeedEntry: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var url: String
    var thumbnailURL: URL?
    var duration: Double?
}

/// A followed channel or playlist whose new uploads download automatically.
nonisolated struct Subscription: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var url: String
    var title: String
    var avatarURL: URL?
    var isAudio = false
    var quality: DownloadQuality = .best
    var addToMusic = true
    var isEnabled = true
    /// Every upload already considered, so only genuinely new ones download.
    var seenIDs: [String] = []
    var downloadedIDs: [String] = []
    var recent: [FeedEntry] = []
    var lastChecked: Date?
    var lastError: String?
    /// New downloads since the subscription was last viewed.
    var unseenCount = 0
    var createdAt = Date()
    var modifiedAt = Date()

    var formatDescription: String {
        isAudio ? "Audio" : quality.rawValue
    }

    func options(from base: DownloadOptions) -> DownloadOptions {
        var options = base
        options.quality = isAudio ? .audio : (quality == .audio ? .best : quality)
        options.addToMusic = addToMusic
        options.downloadPlaylist = false
        options.playlistLimit = 0
        options.clip = nil
        options.subfolder = title
        return options
    }

    /// Keeps the bookkeeping lists from growing forever.
    mutating func trim() {
        if seenIDs.count > 600 { seenIDs = Array(seenIDs.suffix(500)) }
        if downloadedIDs.count > 600 { downloadedIDs = Array(downloadedIDs.suffix(500)) }
    }
}

/// What yt-dlp reports for a channel or playlist.
nonisolated struct Feed: Sendable, Equatable {
    var title: String
    var avatarURL: URL?
    var entries: [FeedEntry]
    /// Set when the link was a channel home page listing tabs (Videos / Shorts / Live)
    /// instead of uploads — fetch this instead.
    var videosTabURL: String?
}

nonisolated enum FeedParser {
    /// A YouTube channel's home page lists tabs, not uploads; point at its Videos tab.
    static func normalize(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              host.hasSuffix("youtube.com") else { return trimmed }
        let pattern = #"^/(@[^/]+|channel/[^/]+|c/[^/]+|user/[^/]+)(/(featured|home))?/?$"#
        if components.path.range(of: pattern, options: .regularExpression) != nil {
            var path = components.path
            for suffix in ["/featured", "/home", "/"] where path.hasSuffix(suffix) {
                path.removeLast(suffix.count)
            }
            components.path = path + "/videos"
            components.query = nil
            return components.string ?? trimmed
        }
        return trimmed
    }

    /// True for links that are clearly a channel or playlist rather than one video.
    static func looksLikeFeed(_ link: String) -> Bool {
        guard let components = URLComponents(string: link) else { return false }
        if components.queryItems?.contains(where: { $0.name == "v" }) == true { return false }
        let path = components.path
        return path.hasPrefix("/@") || path.hasPrefix("/channel/") || path.hasPrefix("/c/")
            || path.hasPrefix("/user/") || path == "/playlist"
    }

    static func parse(_ data: Data) -> Feed? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let rawEntries = json["entries"] as? [[String: Any]] ?? []

        // Channel home pages come back as a list of tabs.
        let tabs = rawEntries.filter { ($0["_type"] as? String) == "playlist" || ($0["ie_key"] as? String) == "YoutubeTab" }
        if !rawEntries.isEmpty, tabs.count == rawEntries.count {
            let videos = tabs.first { ($0["title"] as? String)?.hasSuffix("Videos") == true } ?? tabs[0]
            if let url = (videos["webpage_url"] as? String) ?? (videos["url"] as? String) {
                return Feed(title: "", avatarURL: nil, entries: [], videosTabURL: url)
            }
        }

        func thumbnail(_ object: [String: Any]) -> URL? {
            if let s = object["thumbnail"] as? String, let url = URL(string: s) { return url }
            let thumbs = object["thumbnails"] as? [[String: Any]] ?? []
            return thumbs.reversed().lazy.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.first
        }

        let entries: [FeedEntry] = rawEntries.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            var url = (entry["url"] as? String) ?? (entry["webpage_url"] as? String) ?? ""
            if !url.hasPrefix("http"), (entry["ie_key"] as? String) == "Youtube" {
                url = "https://www.youtube.com/watch?v=\(id)"
            }
            guard url.hasPrefix("http") else { return nil }
            return FeedEntry(id: id,
                             title: (entry["title"] as? String) ?? "Untitled",
                             url: url,
                             thumbnailURL: thumbnail(entry),
                             duration: (entry["duration"] as? NSNumber)?.doubleValue)
        }

        let thumbs = json["thumbnails"] as? [[String: Any]] ?? []
        let avatar = thumbs.first { ($0["id"] as? String)?.hasPrefix("avatar") == true }
            .flatMap { ($0["url"] as? String).flatMap(URL.init(string:)) }

        var title = (json["channel"] as? String) ?? (json["uploader"] as? String) ?? (json["title"] as? String) ?? "Untitled"
        if (json["_type"] as? String) == "playlist", let playlistTitle = json["title"] as? String,
           !(json["id"] as? String ?? "").hasPrefix("UC") {
            title = playlistTitle  // a playlist, not a channel
        }
        for suffix in [" - Videos", " - Shorts", " - Live", " - Home"] where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
        }
        return Feed(title: title, avatarURL: avatar ?? entries.first?.thumbnailURL, entries: entries, videosTabURL: nil)
    }

    /// Uploads not seen before, oldest first so they download in publishing order.
    static func newEntries(in feed: Feed, seen: [String]) -> [FeedEntry] {
        let seenSet = Set(seen)
        return feed.entries.filter { !seenSet.contains($0.id) }.reversed()
    }
}

/// Persists subscriptions in Application Support.
@Observable
final class SubscriptionStore {
    private(set) var items: [Subscription] = []
    /// Deleted subscription IDs, so iCloud sync doesn't bring them back.
    private(set) var tombstones: Set<UUID> = []

    private var fileURL: URL { HistoryStore.supportDirectory.appendingPathComponent("Subscriptions.json") }
    private var tombstoneURL: URL { HistoryStore.supportDirectory.appendingPathComponent("Subscriptions-Deleted.json") }

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL) {
            items = (try? decoder.decode([Subscription].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: tombstoneURL) {
            tombstones = (try? decoder.decode(Set<UUID>.self, from: data)) ?? []
        }
    }

    func subscription(id: UUID) -> Subscription? {
        items.first { $0.id == id }
    }

    func contains(url: String) -> Bool {
        let normalized = FeedParser.normalize(url)
        return items.contains { $0.url == normalized }
    }

    func add(_ subscription: Subscription) {
        items.append(subscription)
        save()
    }

    func update(_ id: UUID, _ change: (inout Subscription) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        items[index].modifiedAt = Date()
        items[index].trim()
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        tombstones.insert(id)
        save()
    }

    /// Replaces everything with a merged set from iCloud sync.
    func replace(with merged: [Subscription], tombstones newTombstones: Set<UUID>) {
        guard merged != items || newTombstones != tombstones else { return }
        items = merged
        tombstones = newTombstones
        save(notify: false)
    }

    private func save(notify: Bool = true) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) { try? data.write(to: fileURL, options: .atomic) }
        if let data = try? encoder.encode(tombstones) { try? data.write(to: tombstoneURL, options: .atomic) }
        if notify { NotificationCenter.default.post(name: .myVideosLocalDataChanged, object: nil) }
    }
}

extension Notification.Name {
    /// Posted when history, subscriptions or settings change, so iCloud sync can push.
    static let myVideosLocalDataChanged = Notification.Name("MyVideosLocalDataChanged")
}
