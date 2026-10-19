//
//  Converter.swift
//  My Videos
//

import Foundation
import Observation

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
