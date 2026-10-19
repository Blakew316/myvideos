//
//  Lyrics.swift
//  My Videos
//

import Foundation

/// Finds song lyrics on LRCLIB (a free, open lyrics database) and writes them into files.
nonisolated enum Lyrics {
    struct Match: Decodable, Sendable, Equatable {
        var trackName: String?
        var artistName: String?
        var duration: Double?
        var plainLyrics: String?
        var syncedLyrics: String?
        var instrumental: Bool?
    }

    private static let userAgent = "My Videos/1.0 (macOS)"

    /// Plain lyrics for a song, or nil when none are found.
    static func find(title: String, artist: String, duration: Double?) async -> String? {
        // Lyrics databases list "Get Lucky", not "Get Lucky (feat. Pharrell Williams)".
        let title = MediaInfo.withoutFeaturing(title.trimmingCharacters(in: .whitespacesAndNewlines))
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }

        // Exact lookup first (fast, precise), then a fuzzy search.
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [URLQueryItem(name: "track_name", value: title),
                            URLQueryItem(name: "artist_name", value: artist)]
        if let duration { exact.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        if let data = await fetch(exact.url), let match = try? JSONDecoder().decode(Match.self, from: data),
           let lyrics = usable(match) {
            return lyrics
        }

        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: title),
                             URLQueryItem(name: "artist_name", value: artist)]
        guard let data = await fetch(search.url),
              let matches = try? JSONDecoder().decode([Match].self, from: data) else { return nil }
        return best(of: matches, duration: duration).flatMap(usable)
    }

    /// The candidate closest in length — remixes and live versions differ by minutes.
    static func best(of matches: [Match], duration: Double?) -> Match? {
        let withLyrics = matches.filter { usable($0) != nil }
        guard let duration else { return withLyrics.first }
        return withLyrics
            .filter { abs(($0.duration ?? duration) - duration) <= 8 }
            .min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
    }

    static func usable(_ match: Match) -> String? {
        if match.instrumental == true { return nil }
        if let plain = match.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return plain
        }
        // Fall back to stripping the [mm:ss.xx] timestamps from synced lyrics.
        guard let synced = match.syncedLyrics, !synced.isEmpty else { return nil }
        let plain = synced.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: #"^\[[\d:.]+\]\s?"#, with: "", options: .regularExpression)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : plain
    }

    private static func fetch(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Writes lyrics into an .m4a or .mp3 in place (stream copy — no re-encoding).
    @discardableResult
    static func embed(_ lyrics: String, in file: URL, ffmpeg: URL) async -> Bool {
        await MediaTags.write(file, tags: nil, lyrics: lyrics, ffmpeg: ffmpeg)
    }
}

/// Reads the title/artist/album tags yt-dlp embedded in a file.
nonisolated enum MediaTags {
    static func read(_ file: URL, ffprobe: URL) async -> MusicTags {
        let args = ["-v", "error", "-show_entries", "format_tags=title,artist,album,album_artist",
                    "-of", "json", file.path]
        guard let output = try? await ProcessRunner.run(ffprobe, args), output.status == 0,
              let json = try? JSONSerialization.jsonObject(with: output.stdout) as? [String: Any],
              let tags = (json["format"] as? [String: Any])?["tags"] as? [String: String] else {
            return MusicTags(title: file.deletingPathExtension().lastPathComponent)
        }
        let lower = Dictionary(tags.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        return MusicTags(title: lower["title"] ?? file.deletingPathExtension().lastPathComponent,
                         artist: lower["artist"] ?? lower["album_artist"] ?? "",
                         album: lower["album"] ?? "")
    }

    /// Rewrites the song details (and optionally lyrics) in an .m4a or .mp3 in place —
    /// a stream copy, so the audio and cover art are untouched.
    @discardableResult
    static func write(_ file: URL, tags: MusicTags?, lyrics: String?, ffmpeg: URL) async -> Bool {
        let ext = file.pathExtension.lowercased()
        guard ext == "m4a" || ext == "mp3" else { return false }
        var metadata: [String] = []
        if let tags {
            for (key, value) in [("title", tags.title), ("artist", tags.artist), ("album", tags.album)]
            where !value.trimmingCharacters(in: .whitespaces).isEmpty {
                metadata += ["-metadata", "\(key)=\(value)"]
            }
        }
        if let lyrics, !lyrics.isEmpty { metadata += ["-metadata", "lyrics=\(lyrics)"] }
        guard !metadata.isEmpty else { return false }

        let temp = file.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(ext)")
        var args = ["-v", "error", "-y", "-i", file.path, "-map", "0:a", "-map", "0:v?", "-c", "copy"] + metadata
        args += ext == "m4a" ? ["-disposition:v", "attached_pic", "-f", "ipod"] : ["-id3v2_version", "3"]
        args.append(temp.path)
        guard let output = try? await ProcessRunner.run(ffmpeg, args), output.status == 0 else {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
        do {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
            return true
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
    }

    static func duration(_ file: URL, ffprobe: URL) async -> Double? {
        let args = ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file.path]
        guard let output = try? await ProcessRunner.run(ffprobe, args), output.status == 0 else { return nil }
        return Double(output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
