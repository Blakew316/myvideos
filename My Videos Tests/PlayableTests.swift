//
//  PlayableTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

struct PlayableTests {
    private func probe(_ video: String, tag: String = "", audio: String? = "aac", subs: [String] = [],
                       width: Int = 1920, height: Int = 1080) -> MediaProbe {
        MediaProbe(duration: 10, video: .init(codec: video, tag: tag, width: width, height: height, isCoverArt: false),
                   hasCoverArt: false, audio: audio, subtitles: subs)
    }

    @Test func appleFriendlyFilesAreLeftAlone() {
        #expect(PlayablePlan.make(for: probe("h264"), fileExtension: "mp4") == nil)
        #expect(PlayablePlan.make(for: probe("hevc", tag: "hvc1"), fileExtension: "mov") == nil)
        #expect(PlayablePlan.make(for: probe("h264", subs: ["mov_text"]), fileExtension: "m4v") == nil)
        #expect(PlayablePlan.make(for: probe("h264", audio: nil), fileExtension: "mp4") == nil)
    }

    @Test func wrongContainerIsRemuxedWithoutReencoding() throws {
        let plan = try #require(PlayablePlan.make(for: probe("h264"), fileExtension: "mkv"))
        #expect(plan.copyVideo && plan.copyAudio)
    }

    @Test func foreignCodecsAreConverted() throws {
        let vp9 = try #require(PlayablePlan.make(for: probe("vp9", audio: "opus"), fileExtension: "mp4"))
        #expect(!vp9.copyVideo && !vp9.copyAudio && !vp9.useHEVC)
        let av1 = try #require(PlayablePlan.make(for: probe("av1"), fileExtension: "mp4"))
        #expect(!av1.copyVideo && av1.copyAudio)
        let mpeg4 = try #require(PlayablePlan.make(for: probe("mpeg4", audio: "mp3"), fileExtension: "avi"))
        #expect(!mpeg4.copyVideo && mpeg4.copyAudio)
        let eightK = try #require(PlayablePlan.make(for: probe("vp9", width: 7680, height: 4320), fileExtension: "webm"))
        #expect(eightK.useHEVC)
    }

    @Test func hev1HEVCIsRetaggedNotReencoded() throws {
        let plan = try #require(PlayablePlan.make(for: probe("hevc", tag: "hev1"), fileExtension: "mp4"))
        #expect(plan.copyVideo)
        let args = plan.ffmpegArguments(input: URL(fileURLWithPath: "/in.mp4"), cover: nil,
                                        output: URL(fileURLWithPath: "/out.mp4"), probe: probe("hevc", tag: "hev1"))
        #expect(args.contains("hvc1"))
    }

    @Test func textSubtitlesBecomeQuickTimeTracks() throws {
        let plan = try #require(PlayablePlan.make(for: probe("h264", subs: ["webvtt"]), fileExtension: "mkv"))
        #expect(plan.keepSubtitles)
        let args = plan.ffmpegArguments(input: URL(fileURLWithPath: "/in.mkv"), cover: nil,
                                        output: URL(fileURLWithPath: "/out.mp4"), probe: probe("h264", subs: ["webvtt"]))
        #expect(args.contains("mov_text"))
        let bitmap = try #require(PlayablePlan.make(for: probe("h264", subs: ["hdmv_pgs_subtitle"]), fileExtension: "mkv"))
        #expect(!bitmap.keepSubtitles)
    }

    @Test func vimeoPageLinksUseThePlayer() {
        #expect(LinkRewrite.forDownloader("https://vimeo.com/1084537") == "https://player.vimeo.com/video/1084537")
        #expect(LinkRewrite.forDownloader("https://www.vimeo.com/123/abc123ef") == "https://player.vimeo.com/video/123?h=abc123ef")
        #expect(LinkRewrite.forDownloader("https://vimeo.com/channels/staffpicks") == "https://vimeo.com/channels/staffpicks")
        #expect(LinkRewrite.forDownloader("https://www.youtube.com/watch?v=x") == "https://www.youtube.com/watch?v=x")
    }

    @Test func videoDownloadsLandInContainersThatHoldArtwork() {
        let args = DownloadOptions(destinationPath: "/tmp").arguments(url: "https://example.com/v.avi", ffmpegDirectory: nil,
                                                                    impersonate: false, cookieArguments: [],
                                                                    printFile: URL(fileURLWithPath: "/tmp/p"))
        #expect(args.contains("--remux-video"))
        var audio = DownloadOptions(destinationPath: "/tmp")
        audio.quality = .audio
        #expect(!audio.arguments(url: "https://example.com", ffmpegDirectory: nil, impersonate: false,
                                 cookieArguments: [], printFile: URL(fileURLWithPath: "/tmp/p")).contains("--remux-video"))
    }
}
