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
        case queued, preparing, downloading, processing, paused, finished, failed, cancelled
    }

    enum MusicState: Equatable {
        case none, evening, findingLyrics, adding, added, failed(String)
    }

    let id = UUID()
    let url: String
    let options: DownloadOptions
    var info: MediaInfo?
    var tags: MusicTags
    /// Set for uploads downloaded automatically from a subscription.
    var subscriptionID: UUID?
    var feedEntryID: String?
    /// Set when this download replaces an older one in History (quality upgrade).
    var replacesHistoryID: UUID?
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
    /// yt-dlp's own error line, kept for "Copy Error Details".
    private(set) var technicalError: String?
    var musicState: MusicState = .none
    /// How many songs got lyrics written into them.
    var lyricsCount = 0

    var isActive: Bool { phase == .preparing || phase == .downloading || phase == .processing }
    var isDone: Bool { phase == .finished || phase == .failed || phase == .cancelled }
    var isWaiting: Bool { phase == .queued || phase == .paused }

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
    private var pauseRequested = false
    private var lastError = ""
    private var printFile: URL?
    private var streamCount = 1
    private var streamIndex = -1
    private var impersonating = false
    /// A network failure was seen in this attempt's output.
    private var networkTrouble = false
    private var toolchain: Toolchain?
    private var converter: PlayableConverter?
    /// Cover art yt-dlp wrote before embedding it; left behind if the download fails.
    private var thumbnailFiles: [URL] = []
    private var log: (String) -> Void = { _ in }
    private var completion: () -> Void = {}
    /// Other ways to try when an attempt fails: without the browser sign-in (stale or
    /// mismatched cookies break some sites) and without browser impersonation (some
    /// sites reset impersonated connections).
    private var fallbacks: [Attempt] = []
    /// Every attempt's error, for Copy Error Details.
    private var attemptErrors: [String] = []

    struct Attempt: Equatable {
        var cookieArguments: [String]
        var impersonate: Bool
        var note: String = ""
    }

    /// The attempts to make, in order, for the given sign-in and impersonation settings.
    nonisolated static func plan(cookieArguments: [String], impersonate: Bool) -> [Attempt] {
        var attempts = [Attempt(cookieArguments: cookieArguments, impersonate: impersonate)]
        if !cookieArguments.isEmpty {
            attempts.append(Attempt(cookieArguments: [], impersonate: impersonate,
                                    note: "Trying again without your browser sign-in…"))
        }
        if impersonate {
            attempts.append(Attempt(cookieArguments: cookieArguments, impersonate: false,
                                    note: "Trying again with a standard connection…"))
        }
        return attempts
    }

    /// Failures another attempt can't fix: retrying would only waste time.
    nonisolated static func isFinal(_ error: String) -> Bool {
        let text = error.lowercased()
        return ["drm", "widevine", "fairplay", "playready", "unsupported url", "is not a valid url",
                "no space left", "permission denied", "read-only file system", "unable to rename",
                "ffmpeg not found", "ffprobe not found"].contains { text.contains($0) }
    }

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
        self.toolchain = toolchain
        reset()

        guard let tool = toolchain.ytdlp else {
            fail("yt-dlp isn’t installed. Open Settings › Advanced to install it.")
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

        var attempts = Self.plan(cookieArguments: cookieArguments, impersonate: toolchain.impersonationAvailable)
        let first = attempts.removeFirst()
        fallbacks = attempts
        attemptErrors = []
        launch(first, tool: tool)
    }

    private func launch(_ attempt: Attempt, tool: URL) {
        let printFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("my-videos-\(id.uuidString).txt")
        self.printFile = printFile
        impersonating = attempt.impersonate
        let args = options.arguments(url: url,
                                     ffmpegDirectory: toolchain?.ffmpeg?.deletingLastPathComponent(),
                                     impersonate: attempt.impersonate,
                                     cookieArguments: attempt.cookieArguments,
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
        statusLine = attempt.note.isEmpty ? "Connecting…" : attempt.note
        if !attempt.note.isEmpty { log(attempt.note) }
        log("$ yt-dlp \(args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " "))")
    }

    /// Stops the transfer but keeps the partial file; resuming picks up where it left off.
    func pause() {
        if phase == .queued {
            phase = .paused
            statusLine = "Paused"
            return
        }
        guard let process, process.isRunning else { return }
        pauseRequested = true
        statusLine = "Pausing…"
        process.terminate()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .queued
        statusLine = "Waiting…"
    }

    func cancel() {
        if phase == .queued || phase == .paused {
            phase = .cancelled
            statusLine = "Cancelled"
            return
        }
        if let converter {
            statusLine = "Stopping…"
            converter.cancel()
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
        thumbnailFiles = []
        errorMessage = nil
        lastError = ""
        networkTrouble = false
        cancelRequested = false
        pauseRequested = false
        streamCount = 1
        streamIndex = -1
        musicState = .none
        lyricsCount = 0
    }

    // MARK: - Output parsing

    private func handle(_ lines: [String]) {
        for line in lines {
            // ffmpeg echoes enormous signed URLs; keep the activity log readable.
            log(line.count > 300 ? String(line.prefix(300)) + "…" : line)

            if line.hasPrefix("ERROR:") || line.contains(" ERROR:") {
                lastError = line
            }
            // ffmpeg fetches clips itself; its network failures come before a bare
            // "ffmpeg exited with code …" that would otherwise read as a broken ffmpeg.
            let lower = line.lowercased()
            if lower.contains("operation timed out") || lower.contains("could not resolve host")
                || lower.contains("connection refused") || lower.contains("network is unreachable")
                || (lower.contains("error opening input") && lower.contains("http")) {
                networkTrouble = true
            }
            if line.contains("Writing video thumbnail"), let path = line.components(separatedBy: " to: ").last {
                thumbnailFiles.append(URL(fileURLWithPath: path))
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

        // A pause that lands just as yt-dlp finishes successfully is no pause at all.
        if pauseRequested && !cancelRequested && (signalled || (status != 0 && status != 101)) {
            pauseRequested = false
            phase = .paused
            statusLine = progressIsIndeterminate ? "Paused" : "Paused at \(Int(progress * 100))%"
            completion()
            return
        }
        if cancelRequested || (signalled && (status == SIGTERM || status == SIGKILL)) {
            phase = .cancelled
            statusLine = "Cancelled"
            progressIsIndeterminate = false
        } else if !savedFiles.isEmpty || status == 0 {
            // 101: --max-downloads stopped yt-dlp after the one file we asked for — but it
            // exits that way even when nothing could be downloaded, so only files count.
            // A playlist can also exit non-zero when a single entry is unavailable, but
            // whatever did download is still a success.
            if options.subtitles == .embed { removeLeftoverSubtitles() }
            if !options.isAudio, let ffmpeg = toolchain?.ffmpeg, let ffprobe = toolchain?.ffprobe {
                makePlayable(ffmpeg: ffmpeg, ffprobe: ffprobe, status: status)
                return
            }
            succeed(status: status)
            return
        } else {
            if !lastError.isEmpty { attemptErrors.append(lastError) }
            if !Self.isFinal(lastError), !fallbacks.isEmpty, let tool = toolchain?.ytdlp {
                let next = fallbacks.removeFirst()
                lastError = ""
                networkTrouble = false
                streamCount = 1
                streamIndex = -1
                progressIsIndeterminate = true
                launch(next, tool: tool)
                return
            }
            fail(friendlyError(code: status))
            return
        }
        completion()
    }

    /// Converts anything QuickTime can't open (WebM, MKV, AVI, VP9, AV1, Opus…) to MP4.
    private func makePlayable(ffmpeg: URL, ffprobe: URL, status: Int32) {
        phase = .processing
        progress = 0
        progressIsIndeterminate = true
        statusLine = "Making it play everywhere…"
        let converter = PlayableConverter()
        self.converter = converter
        Task { @MainActor in
            var files: [URL] = []
            for (index, file) in savedFiles.enumerated() {
                let result = await converter.makePlayable(file, ffmpeg: ffmpeg, ffprobe: ffprobe, log: log) { [weak self] value in
                    guard let self else { return }
                    self.progressIsIndeterminate = false
                    self.progress = (Double(index) + value) / Double(max(1, self.savedFiles.count))
                    self.statusLine = "Converting for QuickTime… \(Int(self.progress * 100))%"
                }
                if converter.cancelled { break }
                files.append(result ?? file)
            }
            self.converter = nil
            if converter.cancelled {
                phase = .cancelled
                statusLine = "Cancelled"
                progressIsIndeterminate = false
                completion()
                return
            }
            savedFiles = files
            succeed(status: status)
        }
    }

    private func succeed(status: Int32) {
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
        completion()
    }

    private func fail(_ message: String) {
        for file in thumbnailFiles { try? FileManager.default.removeItem(at: file) }
        thumbnailFiles = []
        phase = .failed
        errorMessage = message
        let errors = attemptErrors.isEmpty ? [lastError].filter { !$0.isEmpty } : attemptErrors
        technicalError = errors.isEmpty ? nil : errors.joined(separator: "\n")
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

        if has("ip address is blocked", "not available in your country", "geo restrict", "geo-restrict",
               "not available in your region", "blocked it in your country") {
            return "This video isn’t available where you are. The site blocks it for your location or network."
        }
        if networkTrouble || has("getaddrinfo", "network is unreachable", "failed to resolve", "connection reset",
               "timed out", "temporary failure in name resolution", "unable to download webpage: <urlopen",
               "recv failure", "couldn't connect", "could not connect", "could not resolve host") {
            let host = URL(string: url)?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? "the site"
            return "Couldn’t connect to \(host). Check your internet connection; if other sites work, \(host) may be blocked on this network."
        }
        if has("http error 429", "too many requests") {
            return "The site is limiting requests right now. Wait a few minutes, then try again."
        }
        if has("http error 403", "403: forbidden", "403 forbidden", "cloudflare") {
            return impersonating
                ? "The site blocked the download. It may require you to sign in (Settings → Accounts)."
                : "The site blocked the download. Updating yt-dlp in Settings › Advanced often fixes this."
        }
        if has("sign in to confirm", "age-restricted", "age restricted", "not a bot", "login required",
               "requires authentication", "logged-in", "logged in", "private video", "members-only", "join this channel") {
            return "This video needs you to be signed in. Sign in under Settings → Accounts, then try again."
        }
        if has("drm protected", "drm-protected", "is drm", "widevine", "fairplay") {
            return "This video is copy-protected (DRM) by the site, so it can’t be downloaded."
        }
        if has("requested format is not available", "requested format not available", "no video formats found") {
            return "No downloadable stream was found. Try “Audio only”, or check that the link is a video page."
        }
        if has("video unavailable", "this video is unavailable", "has been removed", "does not exist", "post is not available",
               "content isn't available", "no longer available") {
            return "This video has been removed or made private, so it can’t be downloaded."
        }
        if has("unsupported url", "no suitable", "is not a valid url") {
            return "No video was found at this link. Open the video itself (not a search, home or profile page) and copy its address."
        }
        if has("unable to extract", "cannot parse data", "unable to parse") {
            return "The site changed how it shows this video, so it couldn’t be read. Update yt-dlp in Settings › Advanced, or try again later. (\(Self.reason(lastError)))"
        }
        if has("ffmpeg not found", "ffprobe not found", "ffmpeg is not installed") {
            return "ffmpeg is missing. Open Settings › Advanced to install it."
        }
        if has("ffmpeg", "ffprobe") {
            return "ffmpeg couldn’t process this video (\(Self.reason(lastError))). Try another quality, or download without clipping."
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

    /// "ERROR: [youtube] abc: Unable to extract …" → "Unable to extract …"
    static func reason(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "ERROR:", with: "").trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: #"^\[[^\]]+\]\s*[^:]*:\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return text.count > 160 ? String(text.prefix(160)) + "…" : text
    }

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
