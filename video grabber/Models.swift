//
//  Models.swift
//  My Videos
//

import Foundation

// MARK: - Download options

/// Quality / format presets exposed in the UI.
nonisolated enum DownloadQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case best  = "Best quality"
    case p1080 = "1080p"
    case p720  = "720p"
    case audio = "Audio only"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .best:  return "sparkles"
        case .p1080: return "4k.tv"
        case .p720:  return "tv"
        case .audio: return "music.note"
        }
    }

    /// The -S sort keeps the highest resolution but, at equal resolution, prefers
    /// H.264 + AAC — otherwise yt-dlp picks VP9/AV1 + Opus, and the merged .mp4
    /// won't play in QuickTime or import into Photos/Music.
    var formatArguments: [String] {
        let sort = ["-S", "res,fps,vcodec:h264,acodec:aac"]
        switch self {
        case .best:
            return ["-f", "bv*+ba/b"] + sort + ["--merge-output-format", "mp4"]
        case .p1080:
            return ["-f", "bv*[height<=1080]+ba/b[height<=1080]/b"] + sort + ["--merge-output-format", "mp4"]
        case .p720:
            return ["-f", "bv*[height<=720]+ba/b[height<=720]/b"] + sort + ["--merge-output-format", "mp4"]
        case .audio:
            return ["-f", "ba/b"]
        }
    }
}

/// Audio container/codec yt-dlp should transcode extracted audio into.
nonisolated enum AudioFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case m4a, mp3, opus, wav

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m4a:  return "AAC (.m4a)"
        case .mp3:  return "MP3"
        case .opus: return "Opus"
        case .wav:  return "WAV (lossless)"
        }
    }

    /// Apple Music can't import Opus.
    var worksWithAppleMusic: Bool { self != .opus }
    /// Cover art can only be embedded in containers that have a tag for it.
    var supportsArtwork: Bool { self == .m4a || self == .mp3 }
}

/// Target audio bitrate, passed to yt-dlp's --audio-quality.
nonisolated enum AudioBitrate: String, CaseIterable, Identifiable, Codable, Sendable {
    case best = "0"
    case k320 = "320K"
    case k192 = "192K"
    case k128 = "128K"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .best: return "Best available"
        case .k320: return "320 kbps"
        case .k192: return "192 kbps"
        case .k128: return "128 kbps"
        }
    }
}

/// How the app supplies a signed-in session to yt-dlp for private / login-gated videos.
/// Raw values are persisted, so existing ones must not change.
nonisolated enum CookieSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case none    = "No sign-in"
    case builtIn = "Built-in browser"
    case browser = "From a browser"
    case file    = "cookies.txt file"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:    return "Don’t Sign In"
        case .builtIn: return "My Videos Sign-In"
        case .browser: return "Another Browser"
        case .file:    return "cookies.txt File"
        }
    }
}

/// Browsers yt-dlp can pull login cookies from.
nonisolated enum CookieBrowser: String, CaseIterable, Identifiable, Codable, Sendable {
    case chrome, brave, edge, firefox, safari
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .chrome:  return "Chrome"
        case .brave:   return "Brave"
        case .edge:    return "Edge"
        case .firefox: return "Firefox"
        case .safari:  return "Safari"
        }
    }
}

nonisolated enum SubtitleMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, embed, file
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off:   return "Off"
        case .embed: return "In the Video"
        case .file:  return "As a Separate File"
        }
    }
}

nonisolated enum SubtitleLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case en, es, fr, de, it, pt, ja, ko, zh = "zh-Hans", ar, hi, ru
    var id: String { rawValue }
    var displayName: String {
        Locale.current.localizedString(forIdentifier: rawValue) ?? rawValue
    }
    /// Exact codes only: wildcards like "en.*" also match dozens of auto-translated
    /// tracks, and YouTube rate-limits (HTTP 429) the download of all of them.
    var ytdlpCodes: String { "\(rawValue),\(rawValue)-orig" }
}

/// SponsorBlock (YouTube): community-sourced sponsor segments.
nonisolated enum SponsorBlockMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, mark, remove
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .off:    return "Off"
        case .mark:   return "Mark as Chapters"
        case .remove: return "Remove Sponsors"
        }
    }
    var arguments: [String] {
        switch self {
        case .off:    return []
        case .mark:   return ["--sponsorblock-mark", "all"]
        case .remove: return ["--sponsorblock-mark", "all", "--sponsorblock-remove", "sponsor,selfpromo,interaction"]
        }
    }
}

/// How downloads are sorted into folders inside the save location.
nonisolated enum OrganizeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, byType, byChannel, byTypeAndChannel
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:             return "Don’t Organize"
        case .byType:           return "Music and Videos Folders"
        case .byChannel:        return "A Folder for Each Channel"
        case .byTypeAndChannel: return "By Type, Then Channel"
        }
    }
}

nonisolated enum SpeedLimit: Int, CaseIterable, Identifiable, Codable, Sendable {
    case unlimited = 0, one = 1, two = 2, five = 5, ten = 10, twentyFive = 25
    var id: Int { rawValue }
    var displayName: String { self == .unlimited ? "Unlimited" : "\(rawValue) MB/s" }
}

/// Everything that determines how one download runs, snapshotted when it's queued so
/// changing the controls afterwards never changes a download that's already waiting.
nonisolated struct DownloadOptions: Codable, Sendable, Equatable {
    var quality: DownloadQuality = .best
    var audioFormat: AudioFormat = .m4a
    var audioBitrate: AudioBitrate = .best
    var destinationPath: String
    var downloadPlaylist = false
    /// 0 means the whole playlist.
    var playlistLimit = 0
    var clip: ClosedRange<Double>?
    var subtitles: SubtitleMode = .off
    var subtitleLanguage: SubtitleLanguage = .en
    var embedArtwork = true
    var addToMusic = true
    var cookieSource: CookieSource = .none
    var cookieBrowser: CookieBrowser = .chrome
    var cookieFilePath = ""
    var sponsorBlock: SponsorBlockMode = .off
    var organize: OrganizeMode = .none
    var speedLimit: SpeedLimit = .unlimited
    var fetchLyrics = true
    /// Fixed folder inside the destination (subscriptions save into one per channel).
    var subfolder: String?
    /// Even out loudness after downloading (audio).
    var normalizeVolume = false
    /// Replace an existing file with the same name (upgrading a download's quality).
    var forceOverwrite = false

    var isAudio: Bool { quality == .audio }

    /// Folder template prepended to the file name, per the organize setting.
    var folderTemplate: String {
        var parts: [String] = []
        if organize == .byType || organize == .byTypeAndChannel {
            parts.append(isAudio ? "Music" : "Videos")
        }
        if let subfolder, !subfolder.isEmpty {
            // "%" would be read as a template field; "/" would create folders.
            parts.append(subfolder.replacingOccurrences(of: "%", with: "%%").replacingOccurrences(of: "/", with: "-"))
        } else if organize == .byChannel || organize == .byTypeAndChannel {
            parts.append("%(channel,uploader|Other)s")
        }
        return parts.map { $0 + "/" }.joined()
    }
    var destination: URL { URL(fileURLWithPath: destinationPath) }

    /// The full yt-dlp argument list for one download.
    func arguments(url: String, ffmpegDirectory: URL?, impersonate: Bool,
                   cookieArguments: [String], printFile: URL) -> [String] {
        var args = quality.formatArguments
        if isAudio {
            args += ["-x", "--audio-format", audioFormat.rawValue, "--audio-quality", audioBitrate.rawValue]
        }

        // Cap the title (not the whole path) so long titles stay under macOS's 255-byte limit.
        var name = "%(title).150B"
        if let clip {
            args += ["--download-sections", "*\(Timecode.ytdlp(clip.lowerBound))-\(Timecode.ytdlp(clip.upperBound))",
                     "--force-keyframes-at-cuts"]
            name += " (Clip)"
        }
        let template: String
        if downloadPlaylist {
            args += ["--yes-playlist"]
            if playlistLimit > 0 { args += ["--playlist-items", "1:\(playlistLimit)"] }
            template = folderTemplate + "%(playlist_title,playlist_id|Playlist)s/%(playlist_index)03d - \(name).%(ext)s"
        } else {
            // --max-downloads 1 also stops a bare playlist URL from fetching everything.
            args += ["--no-playlist", "--max-downloads", "1"]
            template = folderTemplate + "\(name).%(ext)s"
        }

        if embedArtwork {
            args += ["--embed-metadata", "--embed-chapters"]
            if !isAudio || audioFormat.supportsArtwork {
                args += ["--embed-thumbnail", "--convert-thumbnails", "jpg"]
            }
        }
        // Clipping already cuts the timeline; SponsorBlock removal on top of it fails.
        if clip == nil { args += sponsorBlock.arguments }
        if speedLimit != .unlimited { args += ["--limit-rate", "\(speedLimit.rawValue)M"] }
        if !isAudio, subtitles != .off {
            args += ["--write-subs", "--write-auto-subs", "--sub-langs", subtitleLanguage.ytdlpCodes]
            args += subtitles == .embed ? ["--embed-subs"] : ["--convert-subs", "srt"]
            // YouTube often rate-limits subtitle requests; that must never cost the video itself.
            args += ["--ignore-errors"]
        }
        // Playlists downloaded as audio become an album: numbered tracks under the playlist's name.
        if isAudio && downloadPlaylist {
            if !embedArtwork { args += ["--embed-metadata"] }
            args += ["--parse-metadata", "playlist_index:%(track_number)s",
                     "--parse-metadata", "playlist_title:%(album)s",
                     "--parse-metadata", "playlist_uploader:%(album_artist)s"]
        }
        if forceOverwrite { args += ["--force-overwrites"] }

        args += ["--newline", "--no-mtime",
                 "--retries", "5", "--fragment-retries", "5", "--socket-timeout", "30",
                 "--print-to-file", "after_move:filepath", printFile.path,
                 "-o", destination.appendingPathComponent(template).path]
        if let ffmpegDirectory {
            args += ["--ffmpeg-location", ffmpegDirectory.path]
        }
        if impersonate {
            // Mimic a real browser's TLS fingerprint — defeats Cloudflare / HTTP-403 bot blocks.
            args += ["--impersonate", "chrome"]
        }
        args += cookieArguments
        // "--" so a URL can never be misread as an option.
        args += ["--", url]
        return args
    }
}

/// Title / artist / album applied when a track is added to Apple Music.
nonisolated struct MusicTags: Codable, Sendable, Equatable {
    var title = ""
    var artist = ""
    var album = ""
}

// MARK: - Media info (preview)

/// What yt-dlp reports about a link before downloading it.
nonisolated struct MediaInfo: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var uploader: String?
    var duration: Double?
    var thumbnailURL: URL?
    var webpageURL: String?
    var site: String?
    var isPlaylist: Bool
    var playlistCount: Int?
    var track: String?
    var artist: String?
    var album: String?
    var isLive: Bool
    var channelURL: String?

    static func parse(_ data: Data) -> MediaInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let isPlaylist = (json["_type"] as? String) == "playlist"
        let entries = json["entries"] as? [[String: Any]] ?? []

        func thumbnail(from object: [String: Any]) -> URL? {
            if let s = object["thumbnail"] as? String, let url = URL(string: s) { return url }
            let thumbs = object["thumbnails"] as? [[String: Any]] ?? []
            // Largest last; skip tiny ones that look blurry in the preview.
            for thumb in thumbs.reversed() {
                if let s = thumb["url"] as? String, let url = URL(string: s) { return url }
            }
            return nil
        }

        return MediaInfo(
            id: json["id"] as? String ?? UUID().uuidString,
            title: (json["title"] as? String) ?? (json["fulltitle"] as? String) ?? "Untitled",
            uploader: (json["uploader"] as? String) ?? (json["channel"] as? String),
            duration: (json["duration"] as? NSNumber)?.doubleValue,
            thumbnailURL: thumbnail(from: json) ?? entries.first.flatMap { thumbnail(from: $0) },
            webpageURL: json["webpage_url"] as? String,
            site: json["extractor_key"] as? String,
            isPlaylist: isPlaylist,
            playlistCount: (json["playlist_count"] as? Int) ?? (isPlaylist ? entries.count : nil),
            track: json["track"] as? String,
            artist: (json["artist"] as? String) ?? (json["creator"] as? String),
            album: json["album"] as? String,
            isLive: (json["is_live"] as? Bool) ?? false,
            channelURL: (json["channel_url"] as? String) ?? (json["uploader_url"] as? String)
        )
    }

    /// Best guess at song details: real music metadata when the site has it,
    /// otherwise "Artist - Title" parsed out of the video title.
    var suggestedTags: MusicTags {
        var tags = MusicTags()
        let cleaned = Self.cleanTitle(title)
        if let track, !track.isEmpty {
            tags.title = track
        } else if let range = cleaned.range(of: " - ") {
            tags.title = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            tags.artist = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else {
            tags.title = cleaned
        }
        if let artist, !artist.isEmpty {
            tags.artist = artist.components(separatedBy: ",").first ?? artist
        } else if tags.artist.isEmpty, let uploader {
            tags.artist = uploader
                .replacingOccurrences(of: " - Topic", with: "")
                .replacingOccurrences(of: "VEVO", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        tags.album = album ?? ""
        tags.title = Self.formatFeaturing(tags.title)
        return tags
    }

    /// "Song ft. A, B" → "Song (feat. A, B)", the way Apple Music writes it.
    static func formatFeaturing(_ title: String) -> String {
        let pattern = #"\s+(?:ft\.?|feat\.?|featuring)\s+([^\(\)\[\]]+)$"#
        guard let range = title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return title }
        let guests = title[range]
            .replacingOccurrences(of: #"^\s+(?:ft\.?|feat\.?|featuring)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return title[..<range.lowerBound].trimmingCharacters(in: .whitespaces) + " (feat. \(guests))"
    }

    /// "Song (feat. A)" → "Song", for looking a song up by name.
    static func withoutFeaturing(_ title: String) -> String {
        let pattern = #"\s*[\(\[]?\s*(?:ft\.?|feat\.?|featuring)\s.*$"#
        let base = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? title : base
    }

    /// Strips "(Official Video)", "[Lyrics]" and friends from a title.
    static func cleanTitle(_ title: String) -> String {
        let pattern = #"\s*[\(\[][^\)\]]*\b(official|lyrics?|audio|visuali[sz]er|video|hd|4k|remaster(ed)?)\b[^\)\]]*[\)\]]"#
        let cleaned = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        return cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? title : cleaned.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - History

nonisolated struct HistoryItem: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var uploader: String?
    var sourceURL: String
    var thumbnailURL: URL?
    var filePaths: [String]
    var date: Date
    var isAudio: Bool
    var isPlaylist: Bool
    var duration: Double?
    var byteCount: Int64?
    /// The Mac it was downloaded on (history syncs through iCloud Drive).
    var deviceName: String?
    /// The site's own ID for the video ("Youtube:jNQXAC9IVRw"), for spotting repeats.
    var mediaID: String?
    var subscriptionID: UUID?
    var quality: DownloadQuality?
    /// Last opened from My Videos.
    var lastPlayedAt: Date?
    /// Set when Smart Cleanup moved the file to the Trash.
    var cleanedUpAt: Date?

    var fileURLs: [URL] { filePaths.map { URL(fileURLWithPath: $0) } }
    var primaryFile: URL? { fileURLs.first }
}

// MARK: - Link identity

nonisolated enum LinkIdentity {
    /// A stable key for "the same video", ignoring tracking parameters and URL variants:
    /// youtu.be/ID, youtube.com/watch?v=ID&si=… and /shorts/ID all become "youtube:ID".
    static func key(for link: String) -> String? {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased() else { return nil }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : (host.hasPrefix("m.") ? String(host.dropFirst(2)) : host)
        let path = components.path
        if bareHost == "youtu.be" {
            let id = path.split(separator: "/").first.map(String.init) ?? ""
            return id.isEmpty ? nil : "youtube:\(id)"
        }
        if bareHost.hasSuffix("youtube.com") {
            if let v = components.queryItems?.first(where: { $0.name == "v" })?.value { return "youtube:\(v)" }
            let parts = path.split(separator: "/")
            if parts.count >= 2, ["shorts", "live", "embed"].contains(String(parts[0])) {
                return "youtube:\(parts[1])"
            }
        }
        let trackers: Set<String> = ["si", "feature", "fbclid", "gclid", "ref", "t", "share"]
        let query = (components.queryItems ?? [])
            .filter { !trackers.contains($0.name) && !$0.name.hasPrefix("utm_") }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        var trimmedPath = path
        while trimmedPath.hasSuffix("/") { trimmedPath.removeLast() }
        return bareHost + trimmedPath + (query.isEmpty ? "" : "?" + query)
    }

    static func mediaKey(site: String?, id: String?) -> String? {
        guard let site, let id, !id.isEmpty else { return nil }
        return "\(site):\(id)"
    }
}

// MARK: - Formatting helpers

nonisolated enum Timecode {
    /// 75 → "1:15", 3725 → "1:02:05"
    static func string(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// yt-dlp --download-sections accepts plain seconds with decimals.
    static func ytdlp(_ seconds: Double) -> String {
        String(format: "%.2f", max(0, seconds))
    }

    /// Parses "1:15", "1:02:05" or "75" into seconds.
    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

nonisolated enum ByteSize {
    /// "48.00MiB" → 50331648
    static func parse(_ text: String) -> Double? {
        let pattern = #"([\d.]+)\s*([KMGT]?)(i?)B"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(m.range(at: 1), in: text),
              let value = Double(text[numRange]) else { return nil }
        let unit = Range(m.range(at: 2), in: text).map { String(text[$0]) } ?? ""
        let binary = !(Range(m.range(at: 3), in: text).map { text[$0].isEmpty } ?? true)
        let base: Double = binary ? 1024 : 1000
        let power: Double = ["": 0, "K": 1, "M": 2, "G": 3, "T": 4][unit] ?? 0
        return value * pow(base, power)
    }

    static func string(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
