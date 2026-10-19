//
//  PlayableMedia.swift
//  My Videos
//
//  Every video My Videos saves must open in QuickTime, Photos and Apple's players.
//  Sites and direct links hand back WebM, MKV, AVI, VP9, AV1, Opus, "hev1" HEVC…
//  After a download, anything Apple can't play is remuxed (instant, no quality loss)
//  or, only when the codec itself is the problem, re-encoded on the Mac's media engine.
//

import Foundation

/// The streams in a media file, per ffprobe.
nonisolated struct MediaProbe: Sendable, Equatable {
    struct Video: Sendable, Equatable {
        var codec: String
        var tag: String
        var width: Int
        var height: Int
        var isCoverArt: Bool
    }
    var duration: Double = 0
    /// The main picture (never embedded cover art), if any.
    var video: Video?
    var hasCoverArt = false
    var audio: String?
    /// Codec names of subtitle tracks.
    var subtitles: [String] = []

    static func parse(_ data: Data) -> MediaProbe? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var probe = MediaProbe()
        probe.duration = Double((json["format"] as? [String: Any])?["duration"] as? String ?? "") ?? 0
        for stream in json["streams"] as? [[String: Any]] ?? [] {
            let codec = stream["codec_name"] as? String ?? "?"
            switch stream["codec_type"] as? String {
            case "video":
                let attached = ((stream["disposition"] as? [String: Any])?["attached_pic"] as? Int) == 1
                let cover = attached || codec == "mjpeg" || codec == "png"
                if cover { probe.hasCoverArt = true; continue }
                if probe.video == nil {
                    probe.video = Video(codec: codec, tag: stream["codec_tag_string"] as? String ?? "",
                                        width: stream["width"] as? Int ?? 0, height: stream["height"] as? Int ?? 0,
                                        isCoverArt: false)
                }
            case "audio":
                if probe.audio == nil { probe.audio = codec }
            case "subtitle":
                probe.subtitles.append(codec)
            case "attachment":
                let mime = ((stream["tags"] as? [String: Any])?["mimetype"] as? String) ?? ""
                if mime.hasPrefix("image/") { probe.hasCoverArt = true }
            default: break
            }
        }
        return probe
    }

    static func run(ffprobe: URL, file: URL) async -> MediaProbe? {
        guard let output = try? await ProcessRunner.run(
            ffprobe, ["-v", "error", "-show_format", "-show_streams", "-of", "json", file.path]) else { return nil }
        return parse(output.stdout)
    }
}

/// What it takes to make one file play everywhere on a Mac.
nonisolated struct PlayablePlan: Sendable, Equatable {
    var copyVideo: Bool
    var copyAudio: Bool
    /// Re-encode to HEVC instead of H.264 (pictures larger than H.264 allows).
    var useHEVC: Bool
    var keepSubtitles: Bool

    static let appleVideo: Set<String> = ["h264", "hevc"]
    static let appleAudio: Set<String> = ["aac", "mp3", "alac", "ac3", "eac3"]
    static let appleContainers: Set<String> = ["mp4", "m4v", "mov"]
    static let textSubtitles: Set<String> = ["mov_text", "subrip", "webvtt", "ass", "ssa", "text"]

    /// nil when the file already plays everywhere.
    static func make(for probe: MediaProbe, fileExtension: String) -> PlayablePlan? {
        guard let video = probe.video else { return nil }   // audio files are handled by yt-dlp
        let videoOK = appleVideo.contains(video.codec) && !(video.codec == "hevc" && video.tag == "hev1")
        let audioOK = probe.audio.map(appleAudio.contains) ?? true
        let containerOK = appleContainers.contains(fileExtension.lowercased())
        let subtitlesOK = probe.subtitles.allSatisfy { $0 == "mov_text" }
        if videoOK && audioOK && containerOK && subtitlesOK { return nil }
        return PlayablePlan(copyVideo: appleVideo.contains(video.codec),
                            copyAudio: audioOK,
                            useHEVC: video.width > 4096 || video.height > 2304,
                            keepSubtitles: probe.subtitles.contains(where: textSubtitles.contains))
    }

    /// Hardware-encoder bitrate that keeps the picture indistinguishable from the source.
    static func videoBitrate(height: Int) -> String {
        switch height {
        case 2161...: return "60M"
        case 1441...2160: return "35M"
        case 1081...1440: return "16M"
        case 721...1080: return "8M"
        case 481...720: return "5M"
        default: return "2500k"
        }
    }

    func ffmpegArguments(input: URL, cover: URL?, output: URL, probe: MediaProbe) -> [String] {
        var args = ["-hide_banner", "-nostdin", "-y", "-i", input.path]
        if let cover { args += ["-i", cover.path] }
        args += ["-map", "0:V:0", "-map", "0:a:0?"]
        if keepSubtitles {
            // Only text subtitles can become QuickTime (mov_text) tracks.
            args += ["-map", "0:s?"]
        }
        if cover != nil { args += ["-map", "1:v:0"] }

        if copyVideo {
            args += ["-c:v:0", "copy"]
        } else {
            let height = probe.video?.height ?? 1080
            args += ["-c:v:0", useHEVC ? "hevc_videotoolbox" : "h264_videotoolbox",
                     "-b:v:0", Self.videoBitrate(height: height),
                     "-allow_sw", "1", "-pix_fmt", "yuv420p"]
            if !useHEVC { args += ["-profile:v:0", "high"] }
        }
        if probe.video?.codec == "hevc" || (useHEVC && !copyVideo) { args += ["-tag:v:0", "hvc1"] }
        args += copyAudio ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "256k"]
        if keepSubtitles { args += ["-c:s", "mov_text"] }
        if cover != nil { args += ["-c:v:1", "mjpeg", "-disposition:v:1", "attached_pic"] }
        args += ["-map_metadata", "0", "-map_chapters", "0", "-movflags", "+faststart",
                 "-progress", "pipe:1", "-nostats", output.path]
        return args
    }
}

/// Runs the conversion for one file and swaps it in place of the original.
@MainActor
final class PlayableConverter {
    private var process: StreamingProcess?
    private(set) var cancelled = false

    func cancel() {
        cancelled = true
        process?.terminate()
    }

    /// Returns the playable file (the original when nothing was needed, nil on failure).
    func makePlayable(_ file: URL, ffmpeg: URL, ffprobe: URL, log: (String) -> Void,
                      progress: @escaping (Double) -> Void) async -> URL? {
        guard let probe = await MediaProbe.run(ffprobe: ffprobe, file: file) else { return file }
        guard let plan = PlayablePlan.make(for: probe, fileExtension: file.pathExtension) else { return file }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("my-videos-\(UUID().uuidString)")
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let cover = probe.hasCoverArt ? await extractCover(from: file, ffmpeg: ffmpeg, into: work) : nil
        let output = work.appendingPathComponent("converted.mp4")
        log(plan.copyVideo ? "Repackaging \(file.lastPathComponent) as MP4 so it plays in QuickTime…"
                           : "Converting \(file.lastPathComponent) (\(probe.video?.codec ?? "video")) to \(plan.useHEVC ? "HEVC" : "H.264") so it plays in QuickTime…")

        var ok = await run(ffmpeg, plan.ffmpegArguments(input: file, cover: cover, output: output, probe: probe),
                           duration: probe.duration, progress: progress)
        if !ok && cover != nil && !cancelled {
            // Some cover images can't be carried over; the video matters more.
            ok = await run(ffmpeg, plan.ffmpegArguments(input: file, cover: nil, output: output, probe: probe),
                           duration: probe.duration, progress: progress)
        }
        guard ok, !cancelled, fm.fileExists(atPath: output.path) else { return cancelled ? nil : file }

        var destination = file.deletingPathExtension().appendingPathExtension("mp4")
        if destination != file, fm.fileExists(atPath: destination.path) {
            destination = file.deletingPathExtension().appendingPathExtension("m4v")
        }
        do {
            if destination == file {
                _ = try fm.replaceItemAt(file, withItemAt: output)
            } else {
                try fm.moveItem(at: output, to: destination)
                try? fm.removeItem(at: file)
            }
            return destination
        } catch {
            log("Couldn’t replace \(file.lastPathComponent): \(error.localizedDescription)")
            return file
        }
    }

    private func extractCover(from file: URL, ffmpeg: URL, into folder: URL) async -> URL? {
        let cover = folder.appendingPathComponent("cover.jpg")
        if file.pathExtension.lowercased() == "mkv" || file.pathExtension.lowercased() == "webm" {
            // Matroska keeps artwork as an attachment; ffmpeg can only dump it.
            _ = try? await ProcessRunner.run(ffmpeg, ["-hide_banner", "-nostdin", "-y",
                                                      "-dump_attachment:t:0", cover.path, "-i", file.path])
        } else {
            _ = try? await ProcessRunner.run(ffmpeg, ["-hide_banner", "-nostdin", "-y", "-i", file.path,
                                                      "-map", "0:v", "-map", "-0:V", "-frames:v", "1", "-c", "copy", cover.path])
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: cover.path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 0 ? cover : nil
    }

    private func run(_ ffmpeg: URL, _ args: [String], duration: Double, progress: @escaping (Double) -> Void) async -> Bool {
        let process = StreamingProcess(executable: ffmpeg, arguments: args)
        self.process = process
        defer { self.process = nil }
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            do {
                try process.start(onLines: { lines in
                    for line in lines where line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") {
                        if let micro = Double(line.split(separator: "=").last ?? ""), duration > 0 {
                            progress(min(1, micro / 1_000_000 / duration))
                        }
                    }
                }, onExit: { status, _ in
                    done.resume(returning: status == 0)
                })
            } catch {
                done.resume(returning: false)
            }
        }
    }
}
