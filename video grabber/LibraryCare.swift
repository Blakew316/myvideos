//
//  LibraryCare.swift
//  My Videos
//

import Foundation
import Network
import Observation
import CoreServices

// MARK: - Volume

/// Evens out loudness so songs from different sources play at the same volume.
nonisolated enum AudioTools {
    /// EBU R128 loudness normalization (one pass), keeping cover art and tags.
    /// -16 LUFS matches what Apple Music's Sound Check aims for.
    static func normalize(_ file: URL, ffmpeg: URL) async -> Bool {
        let ext = file.pathExtension.lowercased()
        let codec: [String]
        switch ext {
        case "m4a":  codec = ["-c:a", "aac", "-b:a", "256k", "-f", "ipod"]
        case "mp3":  codec = ["-c:a", "libmp3lame", "-q:a", "2", "-id3v2_version", "3"]
        case "wav":  codec = ["-c:a", "pcm_s16le"]
        case "opus": codec = ["-c:a", "libopus", "-b:a", "160k"]
        default:     return false
        }
        let temp = file.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(ext)")
        var args = ["-v", "error", "-y", "-i", file.path, "-map", "0:a", "-map_metadata", "0"]
        if ext == "m4a" || ext == "mp3" {
            args += ["-map", "0:v?", "-c:v", "copy", "-disposition:v", "attached_pic"]
        }
        args += ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"] + codec + [temp.path]
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
}

// MARK: - Download hours & network

nonisolated enum QuietHours {
    /// Whether `hour` falls in the window [start, end), which may wrap past midnight.
    static func contains(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return true }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Knows whether the Mac is on a metered connection (phone hotspot, Low Data Mode).
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isMetered = false
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let metered = path.isExpensive || path.isConstrained
            Task { @MainActor in NetworkMonitor.shared.isMetered = metered }
        }
        monitor.start(queue: DispatchQueue(label: "MyVideos.network"))
    }
}

// MARK: - Watching

nonisolated enum Playback {
    /// When the file was last opened in any app, as recorded by Spotlight.
    static func lastOpened(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

// MARK: - Storage

nonisolated struct StorageSummary: Sendable {
    struct Entry: Identifiable, Sendable {
        let id: UUID
        let title: String
        let bytes: Int64
        let isAudio: Bool
        let lastOpened: Date?
        let downloaded: Date
        let files: [URL]
    }

    var entries: [Entry] = []
    var videoBytes: Int64 { entries.filter { !$0.isAudio }.reduce(0) { $0 + $1.bytes } }
    var musicBytes: Int64 { entries.filter(\.isAudio).reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { videoBytes + musicBytes }
    var freeBytes: Int64 = 0

    var largest: [Entry] { Array(entries.sorted { $0.bytes > $1.bytes }.prefix(8)) }

    /// Downloads nobody has opened in `days` days (or ever, if older than that).
    func untouched(days: Int, now: Date = Date()) -> [Entry] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return entries.filter { ($0.lastOpened ?? $0.downloaded) < cutoff }.sorted { $0.bytes > $1.bytes }
    }

    static func measure(_ items: [HistoryItem], destination: URL) -> StorageSummary {
        var summary = StorageSummary()
        for item in items {
            let files = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !files.isEmpty else { continue }
            let bytes = files.reduce(Int64(0)) {
                $0 + (((try? FileManager.default.attributesOfItem(atPath: $1.path))?[.size] as? NSNumber)?.int64Value ?? 0)
            }
            let opened = ([item.lastPlayedAt] + files.map(Playback.lastOpened)).compactMap { $0 }.max()
            summary.entries.append(Entry(id: item.id, title: item.title, bytes: bytes, isAudio: item.isAudio,
                                         lastOpened: opened, downloaded: item.date, files: files))
        }
        let values = try? destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        summary.freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return summary
    }
}
