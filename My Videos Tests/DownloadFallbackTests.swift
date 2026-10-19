//
//  DownloadFallbackTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("Download fallbacks and error wording")
struct DownloadFallbackTests {
    @Test func signedInDownloadsTryWithoutSignInThenWithoutImpersonation() {
        let plan = DownloadJob.plan(cookieArguments: ["--cookies", "/c.txt"], impersonate: true)
        #expect(plan.map(\.cookieArguments.isEmpty) == [false, true, false])
        #expect(plan.map(\.impersonate) == [true, true, false])
    }

    @Test func plainDownloadsHaveOnlyTheImpersonationFallback() {
        #expect(DownloadJob.plan(cookieArguments: [], impersonate: true).count == 2)
        #expect(DownloadJob.plan(cookieArguments: [], impersonate: false).count == 1)
    }

    @Test func hopelessFailuresAreNotRetried() {
        #expect(DownloadJob.isFinal("ERROR: [vimeo] 1: This video is DRM protected"))
        #expect(DownloadJob.isFinal("ERROR: Unsupported URL: https://example.com"))
        #expect(!DownloadJob.isFinal("ERROR: [youtube] x: Sign in to confirm you’re not a bot"))
        #expect(!DownloadJob.isFinal("ERROR: [twitch:vod] 1: curl: (35) Recv failure: Connection reset by peer"))
    }

    @Test(arguments: [
        ("ERROR: [TikTok] 674: Your IP address is blocked from accessing this post", "isn’t available where you are"),
        ("ERROR: [facebook] 367: Cannot parse data; please report this issue", "can’t read this"),
        ("ERROR: [twitch:vod] 652: Unable to download JSON metadata: curl: (35) Recv failure: Connection reset by peer", "Couldn’t connect to twitch.tv"),
        ("ERROR: [youtube] abc: Video unavailable", "removed or made private"),
        ("ERROR: [generic] Something brand new went wrong", "Something brand new went wrong"),
    ])
    func previewErrorsSayWhy(error: String, expected: String) {
        let message = AppModel.describeFetchError(error, url: "https://www.twitch.tv/videos/1")
        #expect(message.contains(expected), "\(message)")
    }
}

/// A broken sign-in must not break downloads: the job retries without it.
@MainActor
@Suite("DownloadFallbackLive", .enabled(if: ProcessInfo.processInfo.environment["MEDIA_DIR"] != nil), .timeLimit(.minutes(5)))
struct DownloadFallbackLive {
    @Test func brokenCookiesFallBackAndStillDownload() async throws {
        let toolchain = AppModel.shared.toolchain
        if !toolchain.isReady { await toolchain.refresh() }
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MEDIA_DIR"]!)
        let folder = root.appendingPathComponent("Fallback")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let badCookies = folder.appendingPathComponent("broken-cookies.txt")
        try "this is not a cookies file".write(to: badCookies, atomically: true, encoding: .utf8)

        var options = DownloadOptions(destinationPath: folder.path)
        options.quality = .p720
        options.addToMusic = false
        let job = DownloadJob(url: "https://www.youtube.com/watch?v=jNQXAC9IVRw", options: options, info: nil, tags: MusicTags())
        var log: [String] = []
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            job.start(toolchain: toolchain, cookieArguments: ["--cookies", badCookies.path],
                      log: { log.append($0) }, completion: { done.resume() })
        }
        #expect(job.phase == .finished, "\(job.statusLine) | \(job.technicalError ?? "")")
        #expect(log.contains { $0.contains("without your browser sign-in") })
        #expect(!job.savedFiles.isEmpty)
    }
}
