//
//  Converter.swift
//  My Videos
//

import Foundation
import Observation

/// What a file can be converted into.
nonisolated enum ConvertPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case aac, mp3, wav, compatible, smaller, gif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aac:        return "AAC Audio"
        case .mp3:        return "MP3 Audio"
        case .wav:        return "Lossless Audio"
        case .compatible: return "Compatible Video"
        case .smaller:    return "Smaller Video"
        case .gif:        return "Animated GIF"
        }
    }

    var subtitle: String {
        switch self {
        case .aac:        return "Best for Apple Music"
        case .mp3:        return "Plays anywhere"
        case .wav:        return "Uncompressed WAV"
        case .compatible: return "H.264 for QuickTime & iPhone"
        case .smaller:    return "720p, great for sharing"
        case .gif:        return "Silent, loops forever"
        }
    }

    var symbol: String {
        switch self {
        case .aac:        return "music.note"
        case .mp3:        return "music.quarternote.3"
        case .wav:        return "waveform"
        case .compatible: return "play.rectangle.fill"
        case .smaller:    return "arrow.down.right.and.arrow.up.left"
        case .gif:        return "photo.stack.fill"
        }
    }

    var fileExtension: String {
        switch self {
        case .aac:        return "m4a"
        case .mp3:        return "mp3"
        case .wav:        return "wav"
        case .compatible, .smaller: return "mp4"
        case .gif:        return "gif"
        }
    }

    var needsVideo: Bool { self == .compatible || self == .smaller || self == .gif }
    var shortName: String { self == .smaller ? "Smaller" : (self == .gif ? "GIF" : fileExtension.uppercased()) }

    func arguments(input: URL, output: URL) -> [String] {
        var args = ["-hide_banner", "-nostdin", "-y", "-v", "error", "-i", input.path,
                    "-progress", "pipe:1", "-nostats", "-map_metadata", "0"]
        switch self {
        case .aac:
            args += ["-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart"]
        case .mp3:
            args += ["-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-q:a", "2", "-id3v2_version", "3"]
        case .wav:
            args += ["-map", "0:a:0", "-vn", "-c:a", "pcm_s16le"]
        case .compatible:
            args += ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                     "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case .smaller:
            args += ["-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale=-2:'min(720,ih)'",
                     "-c:v", "libx264", "-preset", "medium", "-crf", "26", "-pix_fmt", "yuv420p",
                     "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]
        case .gif:
            args += ["-map", "0:v:0", "-an",
                     "-vf", "fps=12,scale='min(480,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                     "-loop", "0"]
        }
        return args + [output.path]
    }

    /// "Clip.mov" → "Clip.mp4"; if that exists (or is the input), "Clip (Smaller).mp4", then "… 2".
    static func outputURL(for input: URL, preset: ConvertPreset, exists: (URL) -> Bool) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let ext = preset.fileExtension
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        if candidate.path != input.path && !exists(candidate) { return candidate }
        candidate = dir.appendingPathComponent("\(base) (\(preset.shortName)).\(ext)")
        var n = 2
        while exists(candidate) {
            candidate = dir.appendingPathComponent("\(base) (\(preset.shortName)) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

/// One file being converted by ffmpeg.
@Observable
final class ConvertJob: Identifiable {
    enum Phase: Equatable { case waiting, converting, finished, failed, cancelled }

    let id = UUID()
    let input: URL
    let preset: ConvertPreset
    private(set) var phase: Phase = .waiting
    private(set) var progress: Double = 0
    private(set) var output: URL?
    private(set) var message = "Waiting…"
    private var process: StreamingProcess?
    private var duration: Double?
    private var cancelRequested = false
    private var errorLines: [String] = []

    var isActive: Bool { phase == .converting }

    init(input: URL, preset: ConvertPreset) {
        self.input = input
        self.preset = preset
    }

    func start(ffmpeg: URL, ffprobe: URL?, completion: @escaping () -> Void) {
        phase = .converting
        message = "Preparing…"
        Task {
            if let ffprobe {
                duration = await MediaTags.duration(input, ffprobe: ffprobe)
                if preset.needsVideo, await !Self.hasVideo(input, ffprobe: ffprobe) {
                    fail("This file has no video to convert.")
                    completion()
                    return
                }
            }
            guard !cancelRequested else {
                phase = .cancelled
                message = "Cancelled"
                completion()
                return
            }
            let output = ConvertPreset.outputURL(for: input, preset: preset) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            self.output = output
            let process = StreamingProcess(executable: ffmpeg, arguments: preset.arguments(input: input, output: output))
            do {
                try process.start(onLines: { lines in
                    self.handle(lines)
                }, onExit: { status, _ in
                    self.finish(status: status)
                    completion()
                })
                self.process = process
                message = "Converting…"
            } catch {
                fail("Couldn’t start ffmpeg: \(error.localizedDescription)")
                completion()
            }
        }
    }

    func cancel() {
        cancelRequested = true
        if phase == .waiting {
            phase = .cancelled
            message = "Cancelled"
        }
        process?.terminate()
    }

    private func handle(_ lines: [String]) {
        for line in lines {
            if let seconds = Self.progressSeconds(from: line), let duration, duration > 0 {
                progress = min(max(seconds / duration, 0), 1)
                message = "\(Int(progress * 100))% · \(Timecode.string(seconds)) of \(Timecode.string(duration))"
            } else if !line.contains("=") {
                errorLines.append(line)
            }
        }
    }

    private func finish(status: Int32) {
        process = nil
        if cancelRequested {
            phase = .cancelled
            message = "Cancelled"
            if let output { try? FileManager.default.removeItem(at: output) }
        } else if status == 0, let output, FileManager.default.fileExists(atPath: output.path) {
            phase = .finished
            progress = 1
            message = ByteSize.string(Double(DownloadJob.fileSize(output))) + " · " + output.lastPathComponent
        } else {
            if let output { try? FileManager.default.removeItem(at: output) }
            fail(errorLines.last.map { "Conversion failed: \($0)" } ?? "Conversion failed (ffmpeg exit \(status)).")
        }
    }

    private func fail(_ text: String) {
        phase = .failed
        message = text
    }

    /// ffmpeg -progress reports "out_time_us=12345678" (microseconds; out_time_ms is too, despite the name).
    nonisolated static func progressSeconds(from line: String) -> Double? {
        for key in ["out_time_us=", "out_time_ms="] where line.hasPrefix(key) {
            return Double(line.dropFirst(key.count)).map { $0 / 1_000_000 }
        }
        return nil
    }

    private static func hasVideo(_ file: URL, ffprobe: URL) async -> Bool {
        let args = ["-v", "error", "-select_streams", "v", "-show_entries", "stream=codec_name,disposition",
                    "-of", "json", file.path]
        guard let output = try? await ProcessRunner.run(ffprobe, args),
              let json = try? JSONSerialization.jsonObject(with: output.stdout) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else { return false }
        // Cover art counts as a video stream to ffmpeg; it isn't one here.
        return streams.contains { (($0["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0) == 0 }
    }
}
