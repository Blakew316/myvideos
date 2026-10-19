//
//  LibraryCareTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("Library care")
struct LibraryCareTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=abc123&si=xyz&t=42", "youtube:abc123"),
        ("https://youtu.be/abc123?si=share", "youtube:abc123"),
        ("https://m.youtube.com/watch?v=abc123", "youtube:abc123"),
        ("https://www.youtube.com/shorts/abc123", "youtube:abc123"),
        ("https://vimeo.com/76979871/?utm_source=x", "vimeo.com/76979871"),
        ("https://example.com/video?id=7&ref=home", "example.com/video?id=7"),
    ])
    func linksIdentifyTheSameVideo(link: String, key: String) {
        #expect(LinkIdentity.key(for: link) == key)
    }

    @Test func differentVideosStayDifferent() {
        #expect(LinkIdentity.key(for: "https://youtu.be/a") != LinkIdentity.key(for: "https://youtu.be/b"))
        #expect(LinkIdentity.key(for: "https://example.com/video?id=7") != LinkIdentity.key(for: "https://example.com/video?id=8"))
        #expect(LinkIdentity.mediaKey(site: "Youtube", id: "x") == "Youtube:x")
        #expect(LinkIdentity.mediaKey(site: nil, id: "x") == nil)
    }

    @Test func downloadHoursWrapPastMidnight() {
        #expect(QuietHours.contains(hour: 2, start: 1, end: 6))
        #expect(!QuietHours.contains(hour: 6, start: 1, end: 6))
        #expect(QuietHours.contains(hour: 23, start: 22, end: 6))
        #expect(QuietHours.contains(hour: 3, start: 22, end: 6))
        #expect(!QuietHours.contains(hour: 12, start: 22, end: 6))
        #expect(QuietHours.contains(hour: 12, start: 5, end: 5))
    }

    private func args(_ change: (inout DownloadOptions) -> Void) -> [String] {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        change(&options)
        return options.arguments(url: "https://x/y", ffmpegDirectory: nil, impersonate: false,
                                 cookieArguments: [], printFile: URL(fileURLWithPath: "/tmp/p"))
    }

    @Test func audioPlaylistsBecomeAlbums() {
        let a = args { $0.quality = .audio; $0.downloadPlaylist = true }
        #expect(a.contains("playlist_index:%(track_number)s"))
        #expect(a.contains("playlist_title:%(album)s"))
        let video = args { $0.downloadPlaylist = true }
        #expect(!video.contains("playlist_title:%(album)s"))
        let noArtwork = args { $0.quality = .audio; $0.downloadPlaylist = true; $0.embedArtwork = false }
        #expect(noArtwork.contains("--embed-metadata"))
    }

    @Test func subtitleProblemsNeverCostTheVideo() {
        #expect(args { $0.subtitles = .embed }.contains("--ignore-errors"))
        #expect(!args { $0.subtitles = .off }.contains("--ignore-errors"))
    }

    @Test func upgradesOverwrite() {
        #expect(args { $0.forceOverwrite = true }.contains("--force-overwrites"))
        #expect(!args { _ in }.contains("--force-overwrites"))
    }

    @Test func storageFindsUntouchedDownloads() {
        let now = Date()
        func entry(_ title: String, opened: Date?, downloadedDaysAgo: Double, bytes: Int64) -> StorageSummary.Entry {
            .init(id: UUID(), title: title, bytes: bytes, isAudio: false, lastOpened: opened,
                  downloaded: now.addingTimeInterval(-downloadedDaysAgo * 86400), files: [])
        }
        var summary = StorageSummary()
        summary.entries = [
            entry("Watched yesterday", opened: now.addingTimeInterval(-86400), downloadedDaysAgo: 200, bytes: 10),
            entry("Never opened, old", opened: nil, downloadedDaysAgo: 200, bytes: 50),
            entry("Never opened, new", opened: nil, downloadedDaysAgo: 2, bytes: 99),
            entry("Opened long ago", opened: now.addingTimeInterval(-120 * 86400), downloadedDaysAgo: 300, bytes: 70),
        ]
        #expect(summary.untouched(days: 90, now: now).map(\.title) == ["Opened long ago", "Never opened, old"])
        #expect(summary.totalBytes == 229)
        #expect(summary.largest.first?.title == "Never opened, new")
    }
}
