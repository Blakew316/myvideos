//
//  ConvertPreset.swift
//  My Videos
//

import Foundation

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
        case .compatible: return "Plays on every Apple device"
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
