//
//  AppModel.swift
//  My Videos
//

import AppKit
import Observation
import UserNotifications

enum SidebarItem: Hashable {
    case download, queue, history
}

/// The single source of truth shared by the main window, the menu bar extra,
/// the Services menu and the Share extension's URL hand-off.
@Observable
final class AppModel {
    static let shared = AppModel()

    let prefs = Preferences()
    let toolchain = Toolchain()
    let history = HistoryStore()

    // Navigation
    var selection: SidebarItem? = .download
    var showOnboarding = false
    /// Bumped to ask the composer to focus its link field.
    var focusRequest = 0

    // Queue
    private(set) var jobs: [DownloadJob] = []
    var activeJob: DownloadJob? { jobs.first { $0.isActive } }
    var pendingCount: Int { jobs.filter { $0.isActive || $0.phase == .queued }.count }
    var isBusy: Bool { pendingCount > 0 }

    // Activity log
    private(set) var activityLog = ""

    // Alerts
    struct AppAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var showsAutomationButton = false
    }
    var alert: AppAlert?

    // Composer
    var urlString = "" {
        didSet {
            guard urlString != oldValue else { return }
            urlChanged()
        }
    }
    enum PreviewState: Equatable {
        case empty, loading, loaded(MediaInfo), failed(String)
    }
    private(set) var preview: PreviewState = .empty
    private(set) var playlistPreview: PreviewState = .empty
    var downloadPlaylist = false {
        didSet { if downloadPlaylist != oldValue { playlistToggled() } }
    }
    var playlistLimit = 0
    var clipEnabled = false
    var clipStart: Double = 0
    var clipEnd: Double = 0
    var tags = MusicTags() {
        didSet { if !applyingSuggestedTags { tagsEdited = true } }
    }
    private var tagsEdited = false
    private var applyingSuggestedTags = false
    private var previewTask: Task<Void, Never>?
    private var playlistTask: Task<Void, Never>?

    // Clipboard
    private(set) var clipboardHasLink = false
    private var clipboardChangeCountSeen = -1

    private init() {}

    // MARK: - Launch

    func bootstrap() {
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        Task {
            await toolchain.refresh()
            if !prefs.hasCompletedOnboarding || !toolchain.isReady {
                showOnboarding = true
            }
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
            if prefs.autoCheckUpdates, toolchain.ytdlp != nil,
               (Toolchain.lastUpdateCheck ?? .distantPast) < weekAgo {
                await toolchain.checkForUpdates()
            }
        }
    }

    // MARK: - Composer

    var trimmedURL: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValidURL: Bool {
        guard let url = URL(string: trimmedURL), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// "watch?v=…&list=…" links can be downloaded as one video or as the whole playlist.
    var linkHasPlaylist: Bool {
        if case .loaded(let info) = preview, info.isPlaylist { return true }
        return URLComponents(string: trimmedURL)?.queryItems?.contains { $0.name == "list" } ?? false
    }

    /// What the preview card shows: the playlist when downloading it, otherwise the video.
    var displayedPreview: PreviewState {
        if downloadPlaylist, case .loaded(let info) = preview, !info.isPlaylist {
            return playlistPreview == .empty ? preview : playlistPreview
        }
        return preview
    }

    var previewInfo: MediaInfo? {
        if case .loaded(let info) = preview { return info }
        return nil
    }

    var clipDuration: Double? {
        guard let info = previewInfo, !info.isPlaylist, !info.isLive, let d = info.duration, d > 1 else { return nil }
        return d
    }

    private func urlChanged() {
        previewTask?.cancel()
        playlistTask?.cancel()
        preview = .empty
        playlistPreview = .empty
        downloadPlaylist = false
        playlistLimit = 0
        clipEnabled = false
        clipStart = 0
        clipEnd = 0
        tagsEdited = false
        setSuggestedTags(MusicTags())

        guard isValidURL, toolchain.ytdlp != nil else { return }
        let url = trimmedURL
        preview = .loading
        previewTask = Task { [weak self] in
            // Debounce typing; pastes land instantly anyway.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            let result = await self.fetchInfo(url: url, playlist: false)
            guard !Task.isCancelled, self.trimmedURL == url else { return }
            self.preview = result
            if case .loaded(let info) = result {
                if info.isPlaylist { self.downloadPlaylist = true }
                if let d = info.duration { self.clipEnd = d }
                if !self.tagsEdited { self.setSuggestedTags(info.suggestedTags) }
            }
        }
    }

    private func playlistToggled() {
        guard downloadPlaylist, case .loaded(let info) = preview, !info.isPlaylist,
              playlistPreview == .empty else { return }
        clipEnabled = false
        let url = trimmedURL
        playlistPreview = .loading
        playlistTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.fetchInfo(url: url, playlist: true)
            guard !Task.isCancelled, self.trimmedURL == url else { return }
            self.playlistPreview = result
        }
    }

    private func setSuggestedTags(_ suggested: MusicTags) {
        applyingSuggestedTags = true
        tags = suggested
        applyingSuggestedTags = false
    }

    private func fetchInfo(url: String, playlist: Bool) async -> PreviewState {
        guard let tool = toolchain.ytdlp else { return .failed("yt-dlp isn’t installed.") }
        var args = ["-J", "--no-warnings", "--flat-playlist", "--socket-timeout", "20",
                    playlist ? "--yes-playlist" : "--no-playlist"]
        if toolchain.impersonationAvailable { args += ["--impersonate", "chrome"] }
        args += await cookieArguments(for: prefs.baseOptions)
        args += ["--", url]
        do {
            let output = try await ProcessRunner.run(tool, args)
            if Task.isCancelled { return .empty }
            if output.status == 0, let info = MediaInfo.parse(output.stdout) {
                return .loaded(info)
            }
            let error = output.stderr.split(separator: "\n").last { $0.contains("ERROR") }
                .map { $0.replacingOccurrences(of: "ERROR: ", with: "") } ?? ""
            if error.localizedCaseInsensitiveContains("unsupported url") {
                return .failed("This site isn’t supported.")
            }
            if error.localizedCaseInsensitiveContains("sign in") || error.localizedCaseInsensitiveContains("private") {
                return .failed("This video needs you to be signed in.")
            }
            return .failed("Couldn’t load details for this link.")
        } catch {
            return .failed("Couldn’t load details for this link.")
        }
    }

    /// Queues the link in the composer with the current choices, then clears the composer.
    func downloadFromComposer() {
        guard isValidURL else {
            alert = AppAlert(title: "That doesn’t look like a link",
                             message: "Paste a web address that starts with http:// or https://.")
            return
        }
        var options = prefs.baseOptions
        options.downloadPlaylist = downloadPlaylist
        options.playlistLimit = playlistLimit
        if clipEnabled, let duration = clipDuration, clipEnd - clipStart >= 1,
           clipStart > 0.5 || clipEnd < duration - 0.5 {
            options.clip = clipStart...clipEnd
        }
        var info: MediaInfo?
        if case .loaded(let i) = displayedPreview { info = i }
        enqueue(url: trimmedURL, options: options, info: info, tags: tags)
        urlString = ""
    }

    // MARK: - Queue

    func enqueue(url: String, options: DownloadOptions, info: MediaInfo?, tags: MusicTags) {
        let job = DownloadJob(url: url, options: options, info: info, tags: tags)
        jobs.insert(job, at: 0)
        if prefs.notificationsEnabled { Notifier.requestAuthorization() }
        if info == nil { fillInDetails(for: job) }
        processQueue()
    }

    /// Links queued from the Share menu or Services arrive without a preview —
    /// look the details up in parallel so the row and history get a title and artwork.
    private func fillInDetails(for job: DownloadJob) {
        Task { [weak self] in
            guard let self else { return }
            if case .loaded(let info) = await self.fetchInfo(url: job.url, playlist: job.options.downloadPlaylist) {
                job.info = info
                if job.tags == MusicTags() { job.tags = info.suggestedTags }
            }
        }
    }

    private func processQueue() {
        defer { updateDock() }
        guard activeJob == nil,
              let next = jobs.last(where: { $0.phase == .queued }) else { return }
        Task { [weak self] in
            guard let self else { return }
            let cookies = await self.cookieArguments(for: next.options)
            // It may have been cancelled while cookies were being prepared.
            guard next.phase == .queued, self.activeJob == nil else { return }
            next.start(toolchain: self.toolchain, cookieArguments: cookies,
                       log: { [weak self] line in
                           self?.appendLog(line)
                           self?.updateDock()
                       },
                       completion: { [weak self] in
                           self?.jobFinished(next)
                       })
            self.updateDock()
        }
    }

    private func jobFinished(_ job: DownloadJob) {
        appendLog("")
        switch job.phase {
        case .finished:
            recordHistory(for: job)
            if job.options.isAudio && job.options.addToMusic { addToMusic(job) }
            Notifier.post(title: job.savedFiles.count > 1 ? "Playlist Downloaded" : "Download Complete",
                          body: job.displayTitle, enabled: prefs.notificationsEnabled)
        case .failed:
            Notifier.post(title: "Download Failed",
                          body: "\(job.displayTitle) — \(job.errorMessage ?? "")", enabled: prefs.notificationsEnabled)
        default:
            break
        }
        processQueue()
    }

    func cancel(_ job: DownloadJob) {
        job.cancel()
        updateDock()
        processQueue()
    }

    func retry(_ job: DownloadJob) {
        job.requeue()
        jobs.removeAll { $0.id == job.id }
        jobs.insert(job, at: 0)
        processQueue()
    }

    func remove(_ job: DownloadJob) {
        if job.isActive { job.cancel() }
        jobs.removeAll { $0.id == job.id }
        updateDock()
    }

    func clearFinished() {
        jobs.removeAll { $0.isDone }
    }

    func cancelAll() {
        for job in jobs where job.isActive || job.phase == .queued { job.cancel() }
        updateDock()
    }

    // MARK: - History & Apple Music

    private func recordHistory(for job: DownloadJob) {
        guard !job.savedFiles.isEmpty else { return }
        let size = job.savedFiles.reduce(Int64(0)) { $0 + DownloadJob.fileSize($1) }
        history.add(HistoryItem(title: job.displayTitle,
                                uploader: job.info?.uploader,
                                sourceURL: job.url,
                                thumbnailURL: job.info?.thumbnailURL,
                                filePaths: job.savedFiles.map(\.path),
                                date: Date(),
                                isAudio: job.options.isAudio,
                                isPlaylist: job.savedFiles.count > 1,
                                duration: job.options.clip.map { $0.upperBound - $0.lowerBound } ?? job.info?.duration,
                                byteCount: size))
    }

    private func addToMusic(_ job: DownloadJob) {
        let files = job.savedFiles.filter(MusicLibrary.canImport)
        guard !files.isEmpty else {
            if !job.savedFiles.isEmpty {
                job.musicState = .failed("Apple Music can’t import .\(job.savedFiles[0].pathExtension) files.")
            }
            return
        }
        // Single songs get the edited tags; playlist tracks keep their embedded metadata,
        // with the album name applied to all of them if one was given.
        let tags = files.count == 1 ? job.tags : MusicTags(album: job.tags.album)
        job.musicState = .adding
        Task { [weak self] in
            do {
                for file in files {
                    try await MusicLibrary.add(file, tags: tags)
                    self?.appendLog("Added to Apple Music: \(file.lastPathComponent)")
                }
                job.musicState = .added
            } catch {
                job.musicState = .failed(error.localizedDescription)
                self?.showMusicError(error)
            }
        }
    }

    func addToMusic(_ item: HistoryItem) {
        let files = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else {
            alert = AppAlert(title: "File Not Found", message: "“\(item.title)” has been moved or deleted.")
            return
        }
        Task { [weak self] in
            do {
                for file in files {
                    try await MusicLibrary.add(file, tags: MusicTags())
                }
                self?.alert = AppAlert(title: "Added to Apple Music",
                                       message: "“\(item.title)” is now in your music library.")
            } catch {
                self?.showMusicError(error)
            }
        }
    }

    private func showMusicError(_ error: Error) {
        let denied = (error as? MusicLibrary.ImportError).map {
            if case .permissionDenied = $0 { return true } else { return false }
        } ?? false
        alert = AppAlert(title: denied ? "Allow My Videos to Use Music" : "Couldn’t Add to Apple Music",
                         message: error.localizedDescription,
                         showsAutomationButton: denied)
    }

    func redownload(_ item: HistoryItem) {
        var options = prefs.baseOptions
        options.quality = item.isAudio ? .audio : (prefs.quality == .audio ? .best : prefs.quality)
        options.downloadPlaylist = item.isPlaylist
        enqueue(url: item.sourceURL, options: options, info: nil, tags: MusicTags())
        selection = .queue
    }

    // MARK: - Sign-in

    /// The yt-dlp arguments that supply a signed-in session, per the chosen source.
    func cookieArguments(for options: DownloadOptions) async -> [String] {
        switch options.cookieSource {
        case .none:
            return []
        case .file:
            return options.cookieFilePath.isEmpty ? [] : ["--cookies", options.cookieFilePath]
        case .browser:
            return ["--cookies-from-browser", options.cookieBrowser.rawValue]
        case .builtIn:
            guard let file = await SignInSession.exportCookies() else { return [] }
            return ["--cookies", file.path]
        }
    }

    // MARK: - Clipboard

    /// Checks — without reading it — whether the clipboard holds a web link, so My Videos
    /// can offer to download it without triggering macOS's paste-privacy prompt.
    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard prefs.clipboardDetection, pasteboard.changeCount != clipboardChangeCountSeen else { return }
        let changeCount = pasteboard.changeCount
        Task { [weak self] in
            let patterns = try? await pasteboard.detectedPatterns(for: [\NSPasteboard.DetectedValues.probableWebURL])
            guard let self, pasteboard.changeCount == changeCount else { return }
            self.clipboardHasLink = patterns?.contains(\NSPasteboard.DetectedValues.probableWebURL) ?? false
        }
    }

    func dismissClipboardSuggestion() {
        clipboardChangeCountSeen = NSPasteboard.general.changeCount
        clipboardHasLink = false
    }

    /// Puts pasted text (from a system PasteButton, which never triggers a privacy prompt)
    /// into the composer.
    func paste(_ text: String?) {
        clipboardChangeCountSeen = NSPasteboard.general.changeCount
        clipboardHasLink = false
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selection = .download
        urlString = trimmed
    }

    /// Reads the clipboard into the composer (used by the Paste and Download command).
    @discardableResult
    func pasteFromClipboard() -> Bool {
        clipboardChangeCountSeen = NSPasteboard.general.changeCount
        clipboardHasLink = false
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        selection = .download
        urlString = trimmed
        return isValidURL
    }

    // MARK: - Incoming links (URL scheme, Services, Share extension)

    /// myvideos://download?url=<link>
    func handleIncoming(_ url: URL) {
        guard url.scheme == "myvideos",
              let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value else { return }
        downloadImmediately(link)
    }

    /// Queues a link with the current defaults and brings the queue forward.
    func downloadImmediately(_ link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        var options = prefs.baseOptions
        options.downloadPlaylist = false
        enqueue(url: trimmed, options: options, info: nil, tags: MusicTags())
        selection = .queue
    }

    // MARK: - Log & Dock

    func appendLog(_ line: String) {
        activityLog += line + "\n"
        // The whole log is rendered in one Text view; keep it light.
        if activityLog.utf8.count > 80_000 { activityLog = String(activityLog.suffix(60_000)) }
    }

    func log(_ line: String) { appendLog(line) }

    func updateDock() {
        DockProgress.shared.update(job: activeJob, badgeCount: pendingCount)
    }
}

// MARK: - Notifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Only notifies when My Videos isn't frontmost — otherwise the window already says it.
    static func post(title: String, body: String, enabled: Bool) {
        guard enabled, !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            AppModel.shared.selection = .history
            NSApp.activate()
        }
    }
}

// MARK: - Services menu ("Download with My Videos")

final class ServiceProvider: NSObject {
    @objc func downloadURL(_ pasteboard: NSPasteboard, userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string) ?? ""
        let link = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard URL(string: link)?.scheme?.hasPrefix("http") == true else {
            error.pointee = "The selection isn’t a web link." as NSString
            return
        }
        AppModel.shared.downloadImmediately(link)
        NSApp.activate()
    }
}
