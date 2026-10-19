//
//  MediaMatrixCheck.swift
//  My Videos Tests
//
//  Real downloads through the app's own DownloadJob, across sites, containers, codecs,
//  qualities and audio formats. Every result must exist, have the right streams, and
//  open in AVFoundation (QuickTime, Photos, Apple Music) — not just "a file appeared".
//  Opt-in (it downloads from the internet):
//  TEST_RUNNER_MEDIA_DIR=/folder xcodebuild test -scheme "My Videos" -only-testing:"My Videos Tests/MediaMatrix"
//

import AVFoundation
import Foundation
import Testing
@testable import My_Videos

struct MediaCase: CustomTestStringConvertible, Sendable {
    enum Kind: Sendable { case video, audio(String) }   // audio: expected ffprobe codec_name
    let name: String
    let url: String
    var kind: Kind = .video
    var quality: DownloadQuality = .best
    var audioFormat: AudioFormat = .m4a
    var clip: ClosedRange<Double>?
    var subtitles: SubtitleMode = .off
    var playlistLimit = 0
    /// Highest acceptable height (quality caps).
    var maxHeight: Int?
    var expectSubtitleStream = false
    var testDescription: String { name }

    static let all: [MediaCase] = [
        // YouTube: every quality, link shape and audio format.
        MediaCase(name: "YouTube best", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw"),
        MediaCase(name: "YouTube short link 720p", url: "https://youtu.be/jNQXAC9IVRw", quality: .p720, maxHeight: 720),
        MediaCase(name: "YouTube 1080p (clip)", url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", quality: .p1080,
                  clip: 10...16, maxHeight: 1080),
        MediaCase(name: "YouTube 4K best (AV1/VP9 only, clip)", url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                  clip: 20...25),
        MediaCase(name: "YouTube Shorts", url: "https://www.youtube.com/shorts/tPEE9ZwTmy0"),
        MediaCase(name: "YouTube clip", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw", quality: .p720, clip: 3...9),
        MediaCase(name: "YouTube subtitles embedded", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                  quality: .p720, subtitles: .embed, expectSubtitleStream: true),
        MediaCase(name: "YouTube subtitles as file", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                  quality: .p720, subtitles: .file),
        MediaCase(name: "YouTube audio AAC", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                  kind: .audio("aac"), quality: .audio, audioFormat: .m4a),
        MediaCase(name: "YouTube audio MP3", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                  kind: .audio("mp3"), quality: .audio, audioFormat: .mp3),
        MediaCase(name: "YouTube audio Opus", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                  kind: .audio("opus"), quality: .audio, audioFormat: .opus),
        MediaCase(name: "YouTube audio WAV", url: "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                  kind: .audio("pcm_s16le"), quality: .audio, audioFormat: .wav),
        MediaCase(name: "YouTube playlist (2 songs)", url: "https://www.youtube.com/playlist?list=PLlaN88a7y2_plecYoJxvRFTLHVbIVAOoc",
                  kind: .audio("aac"), quality: .audio, playlistLimit: 2),

        // Other sites.
        MediaCase(name: "Vimeo page link (clip)", url: "https://vimeo.com/1084537", quality: .p720, clip: 30...36, maxHeight: 720),
        MediaCase(name: "Vimeo player link (clip)", url: "https://player.vimeo.com/video/1084537", clip: 40...46),
        MediaCase(name: "Dailymotion", url: "https://www.dailymotion.com/video/x7tgad0", quality: .p720, maxHeight: 720),
        MediaCase(name: "X (Twitter)", url: "https://x.com/SpaceX/status/1732824684683784516", quality: .p720, maxHeight: 720),
        MediaCase(name: "TikTok (HEVC)", url: "https://www.tiktok.com/@scout2015/video/6718335390845095173"),
        MediaCase(name: "Bilibili (hev1 HEVC)", url: "https://www.bilibili.com/video/BV1bK411W797", quality: .p720, clip: 0...6),
        MediaCase(name: "Facebook", url: "https://www.facebook.com/watch/?v=10153231379946729"),
        MediaCase(name: "Streamable", url: "https://streamable.com/dnd1"),
        MediaCase(name: "Rumble (clip)", url: "https://rumble.com/v26pcdc-chill-guy.html", quality: .p720, clip: 30...36),
        MediaCase(name: "SoundCloud song", url: "https://soundcloud.com/forss/flickermood",
                  kind: .audio("aac"), quality: .audio),
        MediaCase(name: "Archive.org (clip)", url: "https://archive.org/details/BigBuckBunny_124", clip: 0...6),
        MediaCase(name: "Wikimedia 4K WebM (clip)", url: "https://commons.wikimedia.org/wiki/File:Big_Buck_Bunny_4K.webm",
                  clip: 0...5),

        // Direct files and streams in every common container.
        MediaCase(name: "Direct MP4", url: "https://www.w3schools.com/html/mov_bbb.mp4"),
        MediaCase(name: "Direct MOV", url: "https://filesamples.com/samples/video/mov/sample_640x360.mov"),
        MediaCase(name: "Direct WebM", url: "https://filesamples.com/samples/video/webm/sample_640x360.webm"),
        MediaCase(name: "Direct MKV", url: "https://filesamples.com/samples/video/mkv/sample_640x360.mkv"),
        MediaCase(name: "Direct AVI", url: "https://filesamples.com/samples/video/avi/sample_640x360.avi"),
        MediaCase(name: "HLS stream (clip)", url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", clip: 0...6),
    ]
}

@MainActor
@Suite("MediaMatrix", .enabled(if: ProcessInfo.processInfo.environment["MEDIA_DIR"] != nil), .timeLimit(.minutes(10)))
struct MediaMatrix {
    private static let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MEDIA_DIR"] ?? "/tmp")

    /// Copy-protected videos must fail clearly — never "finish" with nothing saved.
    @Test func drmProtectedVideoFailsClearly() async throws {
        let toolchain = AppModel.shared.toolchain
        if !toolchain.isReady { await toolchain.refresh() }
        let folder = Self.root.appendingPathComponent("DRM")
        try? FileManager.default.removeItem(at: folder)
        var options = DownloadOptions(destinationPath: folder.path)
        options.addToMusic = false
        let job = DownloadJob(url: "https://vimeo.com/76979871", options: options, info: nil, tags: MusicTags())
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            job.start(toolchain: toolchain, cookieArguments: [], log: { _ in }, completion: { done.resume() })
        }
        #expect(job.phase == .failed)
        #expect(job.statusLine.contains("copy-protected"), "\(job.statusLine)")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: options.destinationPath)) ?? []
        #expect(left.isEmpty, "a failed download left \(left) behind")
    }

    @Test(arguments: MediaCase.all)
    func downloads(_ c: MediaCase) async throws {
        let toolchain = AppModel.shared.toolchain
        if !toolchain.isReady { await toolchain.refresh() }
        let ffprobe = try #require(toolchain.ffprobe)

        let folder = Self.root.appendingPathComponent(c.name.replacingOccurrences(of: "/", with: "-"))
        try? FileManager.default.removeItem(at: folder)
        var options = DownloadOptions(destinationPath: folder.path)
        options.quality = c.quality
        options.audioFormat = c.audioFormat
        options.clip = c.clip
        options.subtitles = c.subtitles
        options.addToMusic = false
        options.fetchLyrics = false
        options.downloadPlaylist = c.playlistLimit > 0
        options.playlistLimit = c.playlistLimit

        let job = DownloadJob(url: c.url, options: options, info: nil, tags: MusicTags())
        var log: [String] = []
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            job.start(toolchain: toolchain, cookieArguments: [], log: { log.append($0) }, completion: { done.resume() })
        }
        try #require(job.phase == .finished,
                     "\(c.name): \(job.statusLine)\n\(job.technicalError ?? log.suffix(8).joined(separator: "\n"))")

        let media = job.savedFiles.filter { !["srt", "vtt", "jpg", "webp"].contains($0.pathExtension.lowercased()) }
        #expect(media.count == max(1, c.playlistLimit), "\(c.name): files \(job.savedFiles.map(\.lastPathComponent))")

        for file in media {
            let probe = try await Probe.run(ffprobe, file)
            #expect(probe.duration > 0.5, "\(c.name): duration \(probe.duration)")
            switch c.kind {
            case .video:
                let video = try #require(probe.video, "\(c.name): no video stream in \(file.lastPathComponent)")
                #expect(["h264", "hevc"].contains(video.codec),
                        "\(c.name): \(video.codec) in \(file.pathExtension) won’t play in QuickTime")
                #expect(["mp4", "mov", "m4v"].contains(file.pathExtension.lowercased()),
                        "\(c.name): saved as .\(file.pathExtension)")
                if video.codec == "hevc" { #expect(video.tag == "hvc1", "\(c.name): HEVC tagged \(video.tag)") }
                if let maxHeight = c.maxHeight { #expect(video.height <= maxHeight, "\(c.name): \(video.height)p") }
                if let audio = probe.audio {
                    #expect(["aac", "mp3", "alac", "ac3", "eac3"].contains(audio), "\(c.name): audio \(audio)")
                }
                if let clip = c.clip {
                    let want = clip.upperBound - clip.lowerBound
                    #expect(abs(probe.duration - want) < 3.5, "\(c.name): clip lasts \(probe.duration)s, wanted \(want)s")
                }
                if c.expectSubtitleStream { #expect(probe.hasSubtitles, "\(c.name): no subtitle track") }
            case .audio(let codec):
                #expect(probe.video == nil || probe.video?.isCoverArt == true, "\(c.name): audio file has a video stream")
                #expect(probe.audio == codec, "\(c.name): audio is \(probe.audio ?? "missing"), wanted \(codec)")
            }
            // Opus isn't something Apple's frameworks open; everything else must.
            if c.audioFormat != .opus || !c.isAudio {
                let playable = try await AVURLAsset(url: file).load(.isPlayable)
                #expect(playable, "\(c.name): AVFoundation can’t play \(file.lastPathComponent)")
            }
        }
        if c.subtitles == .file {
            let dir = media.first?.deletingLastPathComponent() ?? folder
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            #expect(names.contains { $0.hasSuffix(".srt") }, "\(c.name): no .srt beside the video (\(names))")
        }
    }
}

private extension MediaCase {
    var isAudio: Bool { if case .audio = kind { return true } else { return false } }
}

/// The streams in a file, per ffprobe.
struct Probe {
    struct Video { let codec: String; let tag: String; let height: Int; let isCoverArt: Bool }
    var duration: Double = 0
    var video: Video?
    var audio: String?
    var hasSubtitles = false

    static func run(_ ffprobe: URL, _ file: URL) async throws -> Probe {
        let output = try await ProcessRunner.run(ffprobe, ["-v", "error", "-show_format", "-show_streams", "-of", "json", file.path])
        let json = try #require(try JSONSerialization.jsonObject(with: output.stdout) as? [String: Any])
        var probe = Probe()
        probe.duration = Double((json["format"] as? [String: Any])?["duration"] as? String ?? "") ?? 0
        for stream in json["streams"] as? [[String: Any]] ?? [] {
            let codec = stream["codec_name"] as? String ?? "?"
            switch stream["codec_type"] as? String {
            case "video":
                let attached = ((stream["disposition"] as? [String: Any])?["attached_pic"] as? Int) == 1
                let video = Video(codec: codec, tag: stream["codec_tag_string"] as? String ?? "",
                                  height: stream["height"] as? Int ?? 0, isCoverArt: attached || codec == "mjpeg" || codec == "png")
                if probe.video == nil || probe.video?.isCoverArt == true { probe.video = video }
            case "audio":
                if probe.audio == nil { probe.audio = codec }
            case "subtitle":
                probe.hasSubtitles = true
            default: break
            }
        }
        return probe
    }
}
