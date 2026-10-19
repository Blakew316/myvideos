//
//  MediaSnifferTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("Finding video on any page")
struct MediaSnifferTests {
    private let base = URL(string: "https://example.com/watch/1")!

    @Test func readsVideoTagsOpenGraphAndLinks() {
        let html = """
        <html><head><title>Fallback</title>
        <meta property="og:title" content="Sunset &amp; Waves">
        <meta property="og:image" content="/art.jpg">
        <meta property="og:video" content="https://cdn.example.com/clip.mp4">
        </head><body><video src="/media/movie.webm"></video>
        <script>var cfg = {"hls":"https:\\/\\/cdn.example.com\\/live\\/master.m3u8"};</script>
        <a href="https://ads.doubleclick.net/preroll.mp4">ad</a></body></html>
        """
        let page = MediaSniffer.parse(html: html, base: base)
        #expect(page.title == "Sunset & Waves")
        #expect(page.imageURL?.absoluteString == "https://example.com/art.jpg")
        #expect(page.mediaURLs.first?.absoluteString == "https://cdn.example.com/live/master.m3u8")  // manifests first
        #expect(page.mediaURLs.contains(URL(string: "https://example.com/media/movie.webm")!))
        #expect(page.mediaURLs.contains(URL(string: "https://cdn.example.com/clip.mp4")!))
        #expect(!page.mediaURLs.contains { $0.absoluteString.contains("doubleclick") })
    }

    @Test func pagesWithoutVideoFindNothing() {
        let page = MediaSniffer.parse(html: "<html><title>Text</title><img src='a.jpg'></html>", base: base)
        #expect(page.mediaURLs.isEmpty)
        #expect(page.title == "Text")
    }

    @Test func onlyUnknownSitesAreSniffed() {
        #expect(DownloadJob.isUnsupported("ERROR: Unsupported URL: https://example.com/x"))
        #expect(!DownloadJob.isUnsupported("ERROR: [youtube] x: Video unavailable"))
    }
}

/// Pages served locally (see the test's SNIFF_BASE): video added by script, HLS, DRM, none.
@MainActor
@Suite("MediaSnifferLive", .enabled(if: ProcessInfo.processInfo.environment["SNIFF_BASE"] != nil), .timeLimit(.minutes(5)))
struct MediaSnifferLive {
    private let base = ProcessInfo.processInfo.environment["SNIFF_BASE"] ?? ""
    private let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MEDIA_DIR"] ?? NSTemporaryDirectory())

    private func download(_ page: String) async -> DownloadJob {
        let toolchain = AppModel.shared.toolchain
        if !toolchain.isReady { await toolchain.refresh() }
        let folder = root.appendingPathComponent("Sniff-\(page)")
        try? FileManager.default.removeItem(at: folder)
        var options = DownloadOptions(destinationPath: folder.path)
        options.quality = .p720
        options.addToMusic = false
        options.clip = page == "hls" ? 0...6 : nil
        let job = DownloadJob(url: "\(base)/\(page).html", options: options, info: nil, tags: MusicTags())
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            job.start(toolchain: toolchain, cookieArguments: [], log: { _ in }, completion: { done.resume() })
        }
        return job
    }

    @Test func scriptAddedVideoDownloadsUnderThePageTitle() async {
        let job = await download("js")
        #expect(job.phase == .finished, "\(job.statusLine) | \(job.technicalError ?? "")")
        #expect(job.savedFiles.first?.lastPathComponent.hasPrefix("Community Clip - Bunny") == true,
                "\(job.savedFiles.map(\.lastPathComponent))")
    }

    @Test func streamingPageDownloads() async {
        let job = await download("hls")
        #expect(job.phase == .finished, "\(job.statusLine) | \(job.technicalError ?? "")")
    }

    @Test func drmPageIsReportedAsProtected() async {
        let job = await download("drm")
        #expect(job.phase == .failed)
        #expect(job.statusLine.contains("copy-protected"), "\(job.statusLine)")
    }

    @Test func pageWithoutVideoSaysSo() async {
        let job = await download("none")
        #expect(job.phase == .failed)
        #expect(job.statusLine.contains("No public video"), "\(job.statusLine)")
    }
}
