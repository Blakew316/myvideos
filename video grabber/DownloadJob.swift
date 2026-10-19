//
//  DownloadJob.swift
//  My Videos
//

import Foundation
import Observation

/// One link in the queue: runs yt-dlp and turns its output into rich progress.
@Observable
final class DownloadJob: Identifiable {
    enum Phase: Equatable {
        case queued, preparing, downloading, processing, finished, failed, cancelled
    }

    enum MusicState: Equatable {
        case none, adding, added, failed(String)
    }

    let id = UUID()
    let url: String
    let options: DownloadOptions
    var info: MediaInfo?
    var tags: MusicTags
    let createdAt = Date()

    private(set) var phase: Phase = .queued
    private(set) var progress: Double = 0
    private(set) var progressIsIndeterminate = true
    private(set) var statusLine = "Waiting…"
    private(set) var currentFile = ""
    private(set) var itemIndex = 0
    private(set) var itemCount = 0
    private(set) var savedFiles: [URL] = []
    private(set) var errorMessage: String?
    var musicState: MusicState = .none

    var isActive: Bool { phase == .preparing || phase == .downloading || phase == .processing }
    var isDone: Bool { phase == .finished || phase == .failed || phase == .cancelled }

    var displayTitle: String {
        if let title = info?.title, !title.isEmpty { return title }
        if !currentFile.isEmpty { return (currentFile as NSString).deletingPathExtension }
        return URL(string: url)?.host(percentEncoded: false) ?? url
    }

    var subtitle: String {
        var parts: [String] = []
        if let uploader = info?.uploader { parts.append(uploader) }
        parts.append(options.isAudio ? "Audio" : options.quality.rawValue)
        if options.clip != nil { parts.append("Clip") }
        if options.downloadPlaylist { parts.append("Playlist") }
        return parts.joined(separator: " · ")
    }

    // Internals
    private var process: StreamingProcess?
    private var cancelRequested = false
    private var lastError = ""
    private var printFile: URL?
    private var streamCount = 1
    private var streamIndex = -1
    private var impersonating = false
    private var log: (String) -> Void = { _ in }
    private var completion: () -> Void = {}

    init(url: String, options: DownloadOptions, info: MediaInfo?, tags: MusicTags) {
        self.url = url
        self.options = options
        self.info = info
        self.tags = tags
    }

    // MARK: - Lifecycle

    func start(toolchain: Toolchain, cookieArguments: [String],
               log: @escaping (String) -> Void, completion: @escaping () -> Void) {
        guard !isActive else { return }
        self.log = log
        self.completion = completion
        reset()

        guard let tool = toolchain.ytdlp else {
            fail("yt-dlp isn’t installed. Open Settings → Components to install it.")
            return
        }
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            fail("App Sandbox is on, so downloads are blocked. Remove the App Sandbox capability in Xcode and run again.")
            return
        }
        if options.cookieSource == .file, !FileManager.default.fileExists(atPath: options.cookieFilePath) {
            fail("The cookies.txt file can’t be found. Choose it again in Settings → Accounts.")
            return
        }
        try? FileManager.default.createDirectory(at: options.destination, withIntermediateDirectories: true)

        let printFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-videos-\(id.uuidString).txt")
        self.printFile = printFile
        impersonating = toolchain.impersonationAvailable
        let args = options.arguments(url: url,
                                     ffmpegDirectory: toolchain.ffmpeg?.deletingLastPathComponent(),
                                     impersonate: impersonating,
                                     cookieArguments: cookieArguments,
                                     printFile: printFile)

        let process = StreamingProcess(executable: tool, arguments: args)
        do {
            try process.start(onLines: { [weak self] lines in
                self?.handle(lines)
            }, onExit: { [weak self] status, signalled in
                self?.finish(status: status, signalled: signalled)
            })
        } catch {
            fail("Couldn’t launch yt-dlp: \(error.localizedDescription)")
            return
        }
        self.process = process
        phase = .preparing
        statusLine = "Connecting…"
        log("$ yt-dlp \(args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " "))")
    }

    func cancel() {
        if phase == .queued {
            phase = .cancelled
            statusLine = "Cancelled"
            return
        }
        guard let process, process.isRunning else { return }
        cancelRequested = true
        statusLine = "Stopping…"
        process.terminate()
    }

    /// Puts a failed or cancelled job back in line.
    func requeue() {
        guard isDone else { return }
        reset()
        phase = .queued
        statusLine = "Waiting…"
    }

    private func reset() {
        progress = 0
        progressIsIndeterminate = true
        currentFile = ""
        itemIndex = 0
        itemCount = 0
        savedFiles = []
        errorMessage = nil
        lastError = ""
        cancelRequested = false
        streamCount = 1
        streamIndex = -1
        musicState = .none
    }

    // MARK: - Output parsing

    private func handle(_ lines: [String]) {
        for line in lines {
            // ffmpeg echoes enormous signed URLs; keep the activity log readable.
            log(line.count > 300 ? String(line.prefix(300)) + "…" : line)

            if line.hasPrefix("ERROR:") || line.contains(" ERROR:") {
                lastError = line
            }
            if let formats = Self.capture(line, #"Downloading \d+ format\(s\): (\S+)"#) {
                streamCount = max(1, formats.split(separator: "+").count)
                streamIndex = -1
            }
            if let index = Self.capture(line, #"^\[download\] Downloading item (\d+) of"#),
               let total = Self.capture(line, #"of (\d+)$"#) {
                itemIndex = Int(index) ?? 0
                itemCount = Int(total) ?? 0
                streamIndex = -1
            }
            if let dest = Self.capture(line, #"^\[download\] Destination: (.+)$"#) {
                currentFile = (dest as NSString).lastPathComponent
                streamIndex = min(streamIndex + 1, streamCount - 1)
                phase = .downloading
            }
            if let dest = Self.capture(line, #"^\[download\] (.+) has already been downloaded$"#) {
                currentFile = (dest as NSString).lastPathComponent
            }
            if let dest = Self.capture(line, #"^\[(?:ExtractAudio|Merger)\] (?:Destination: |Merging formats into ")(.+?)"?$"#) {
                currentFile = (dest as NSString).lastPathComponent
            }

            if let step = Self.processingStep(for: line) {
                phase = .processing
                progressIsIndeterminate = true
                statusLine = prefixed(step)
                continue
            }

            if let pct = Self.capture(line, #"^\[download\]\s+([\d.]+)%"#).flatMap(Double.init) {
                phase = .downloading
                updateProgress(fraction: pct / 100, line: line)
            } else if phase == .downloading, let clip = options.clip,
                      let time = Self.capture(line, #"time=(\d+:\d+:[\d.]+)"#).flatMap(Timecode.parse) {
                // Clipped downloads go through ffmpeg, which reports elapsed media time.
                let length = max(clip.upperBound - clip.lowerBound, 1)
                updateProgress(fraction: min(time / length, 1), line: nil)
            }
        }
    }

    private func updateProgress(fraction: Double, line: String?) {
        let streamFraction = (Double(max(streamIndex, 0)) + fraction) / Double(streamCount)
        if itemCount > 0 {
            progress = (Double(max(itemIndex - 1, 0)) + streamFraction) / Double(itemCount)
        } else {
            progress = streamFraction
        }
        progress = min(max(progress, 0), 1)
        progressIsIndeterminate = false

        guard let line else {
            statusLine = prefixed("Downloading…")
            return
        }
        // "[download]  42.0% of  302.04KiB at    2.78MiB/s ETA 00:12"
        var parts: [String] = []
        if let total = Self.capture(line, #"of\s+~?\s*([\d.]+\s*[KMGT]?i?B)"#).flatMap(ByteSize.parse) {
            parts.append("\(ByteSize.string(total * fraction)) of \(ByteSize.string(total))")
        }
        if let speed = Self.capture(line, #"at\s+([\d.]+\s*[KMGT]?i?B)/s"#).flatMap(ByteSize.parse) {
            parts.append("\(ByteSize.string(speed))/s")
        }
        if let eta = Self.capture(line, #"ETA\s+([\d:]+)"#).flatMap(Timecode.parse), eta > 0, fraction < 1 {
            parts.append(Self.remaining(eta))
        }
        statusLine = prefixed(parts.isEmpty ? "Downloading…" : parts.joined(separator: " · "))
    }

    private func prefixed(_ text: String) -> String {
        itemCount > 1 ? "Video \(itemIndex) of \(itemCount) — \(text)" : text
    }

    private static func processingStep(for line: String) -> String? {
        if line.hasPrefix("[Merger]") { return "Combining video and audio…" }
        if line.hasPrefix("[ExtractAudio]") { return "Converting audio…" }
        if line.hasPrefix("[EmbedThumbnail]") || line.hasPrefix("[ThumbnailsConvertor]") { return "Adding cover art…" }
        if line.hasPrefix("[EmbedSubtitle]") || line.hasPrefix("[SubtitlesConvertor]") { return "Adding subtitles…" }
        if line.hasPrefix("[Metadata]") { return "Writing details…" }
        if line.hasPrefix("[VideoConvertor]") || line.hasPrefix("[FixupM3u8]") || line.hasPrefix("[FixupM4a]") {
            return "Finishing up…"
        }
        return nil
    }

    private static func remaining(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s) sec left" }
        if s < 3600 { return "\(s / 60) min left" }
        return "\(s / 3600) hr \((s % 3600) / 60) min left"
    }

    // MARK: - Completion

    private func finish(status: Int32, signalled: Bool) {
        process = nil
        if let printFile {
            let printed = (try? String(contentsOf: printFile, encoding: .utf8)) ?? ""
            savedFiles = printed.split(whereSeparator: \.isNewline)
                .map { URL(fileURLWithPath: String($0)) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            try? FileManager.default.removeItem(at: printFile)
            self.printFile = nil
        }

        if cancelRequested || (signalled && (status == SIGTERM || status == SIGKILL)) {
            phase = .cancelled
            statusLine = "Cancelled"
            progressIsIndeterminate = false
        } else if status == 0 || status == 101 || !savedFiles.isEmpty {
            // 101: --max-downloads stopped yt-dlp after the one file we asked for.
            // A playlist can also exit non-zero when a single entry is unavailable, but
            // whatever did download is still a success.
            if options.subtitles == .embed { removeLeftoverSubtitles() }
            phase = .finished
            progress = 1
            progressIsIndeterminate = false
            if let first = savedFiles.first { currentFile = first.lastPathComponent }
            let size = savedFiles.reduce(Int64(0)) { $0 + Self.fileSize($1) }
            if savedFiles.count > 1 {
                statusLine = "\(savedFiles.count) files · \(ByteSize.string(Double(size)))"
                if status != 0 && status != 101 { statusLine += " · some videos were unavailable" }
            } else {
                statusLine = size > 0 ? "\(ByteSize.string(Double(size))) · Saved to \(options.destination.lastPathComponent)"
                                      : "Saved to \(options.destination.lastPathComponent)"
            }
        } else {
            fail(friendlyError(code: status))
            return
        }
        completion()
    }

    private func fail(_ message: String) {
        phase = .failed
        errorMessage = message
        statusLine = message
        progressIsIndeterminate = false
        completion()
    }

    /// --embed-subs leaves the sidecar file behind when combined with clipping.
    private func removeLeftoverSubtitles() {
        let fm = FileManager.default
        for file in savedFiles {
            let base = file.deletingPathExtension().lastPathComponent
            let dir = file.deletingLastPathComponent()
            let siblings = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in siblings where name.hasPrefix(base + ".") && (name.hasSuffix(".vtt") || name.hasSuffix(".srt")) {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Turns yt-dlp's raw failure into a clear, actionable sentence.
    private func friendlyError(code: Int32) -> String {
        // Only inspect yt-dlp's actual ERROR line — scanning the whole log mislabels failures.
        let haystack = lastError.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { haystack.contains($0) } }

        if has("getaddrinfo", "network is unreachable", "failed to resolve", "connection reset",
               "timed out", "temporary failure in name resolution", "unable to download webpage: <urlopen") {
            return "Network problem — check your internet connection and try again."
        }
        if has("http error 429", "too many requests") {
            return "The site is limiting requests right now. Wait a few minutes, then try again."
        }
        if has("http error 403", "403: forbidden", "403 forbidden", "cloudflare") {
            return impersonating
                ? "The site blocked the download. It may require you to sign in (Settings → Accounts)."
                : "The site blocked the download. Updating yt-dlp in Settings → Components often fixes this."
        }
        if has("sign in to confirm", "age-restricted", "age restricted", "not a bot", "login required",
               "requires authentication", "logged-in", "logged in", "private video", "members-only", "join this channel") {
            return "This video needs you to be signed in. Sign in under Settings → Accounts, then try again."
        }
        if has("requested format is not available", "requested format not available", "no video formats found") {
            return "No downloadable stream was found. Try “Audio only”, or check that the link is a video page."
        }
        if has("unsupported url", "no suitable", "unable to extract", "is not a valid url") {
            return "This link isn’t supported. Make sure it points directly at a video. Updating yt-dlp can also help."
        }
        if has("ffmpeg", "ffprobe") {
            return "ffmpeg is missing or failed. Open Settings → Components to install it."
        }
        if has("unable to rename", "permission denied", "read-only file system", "no space left") {
            return "Couldn’t save the file — check the folder’s permissions and free space."
        }
        if has("could not copy", "unable to open database", "cookie", "could not find") {
            switch options.cookieSource {
            case .browser:
                return "Couldn’t read \(options.cookieBrowser.displayName)’s sign-in. Try “My Videos Sign-In” in Settings → Accounts instead."
            case .file:
                return "That cookies.txt couldn’t be used. Export it again while signed in."
            case .builtIn, .none:
                return "This video needs you to be signed in. Sign in under Settings → Accounts, then try again."
            }
        }
        if has("drm protected", "drm-protected", "protected by drm", "widevine", "playready") {
            return "This video is copy-protected (DRM), so it can’t be downloaded."
        }
        if !lastError.isEmpty {
            let cleaned = lastError
                .replacingOccurrences(of: "ERROR:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return "Download failed: \(cleaned)"
        }
        return "Download failed (exit \(code)). The activity log has details."
    }

    // MARK: - Helpers

    private static var regexCache: [String: NSRegularExpression] = [:]

    private static func capture(_ line: String, _ pattern: String) -> String? {
        let re: NSRegularExpression
        if let cached = regexCache[pattern] {
            re = cached
        } else {
            guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
            regexCache[pattern] = compiled
            re = compiled
        }
        guard let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return String(line[r]).trimmingCharacters(in: .whitespaces)
    }
}
