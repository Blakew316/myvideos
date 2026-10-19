//
//  AppModel.swift
//  My Videos
//

import AppKit
import Observation
import SystemConfiguration
import UserNotifications

enum SidebarItem: Hashable {
    case download, queue, history, convert, subscriptions
    case subscription(UUID)
}

/// The single source of truth shared by the main window, the menu bar extra, App Intents,
/// the Services menu and the Share extension's URL hand-off.
@Observable
final class AppModel {
    static let shared = AppModel()

    let prefs = Preferences()
    let toolchain = Toolchain()
    let history = HistoryStore()
    let subscriptions = SubscriptionStore()
    let sync = SyncService()
    let signIn = SignInStatus()

    /// The Mac's name as shown in Sharing settings, recorded with each download.
    static let deviceName: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "This Mac"

    /// Running inside the unit-test host: skip timers, sync and other side effects.
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    // Navigation
    var selection: SidebarItem? = .download
    var showOnboarding = false
    /// Bumped to ask the composer to focus its link field.
    var focusRequest = 0
    /// Presents the Subscribe sheet, optionally prefilled with a link.
    var subscribeRequest: SubscribeRequest?

    struct SubscribeRequest: Identifiable {
        let id = UUID()
        var link: String
    }

    // Queue (oldest first: the top of "Up Next" runs next)
    private(set) var jobs: [DownloadJob] = []
    private var starting: Set<UUID> = []
    var activeJobs: [DownloadJob] { jobs.filter(\.isActive) }
    var activeJob: DownloadJob? { activeJobs.first }
    var pendingCount: Int { jobs.filter { $0.isActive || $0.phase == .queued }.count }
    var pausedCount: Int { jobs.filter { $0.phase == .paused }.count }
    var isBusy: Bool { pendingCount > 0 || conversions.contains(where: \.isActive) }

    // Conversions
    private(set) var conversions: [ConvertJob] = []
    /// The conversion ffmpeg is working on — tracked separately so removing it from the
    /// list doesn't let a second one start before ffmpeg has actually stopped.
    private var runningConversion: ConvertJob?
    /// Files dropped on the Dock icon, waiting for a format choice.
    var stagedFiles: [URL] = []
    var convertPreset: ConvertPreset = ConvertPreset(rawValue: UserDefaults.standard.string(forKey: "convertPreset") ?? "") ?? .compatible {
        didSet { UserDefaults.standard.set(convertPreset.rawValue, forKey: "convertPreset") }
    }

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

    // Subscriptions
    private(set) var checkingSubscriptions: Set<UUID> = []
    private var subscriptionTimer: Task<Void, Never>?

    private init() {}

    // MARK: - Launch

    func bootstrap() {
        guard !Self.isTesting else { return }
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Diagnostics.shared.start()

        NotificationCenter.default.addObserver(forName: .myVideosLocalDataChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.sync.scheduleSync(model: AppModel.shared) }
        }
        sync.configure(enabled: prefs.iCloudSync, model: self)
        CompanionServer.shared.handler = { await CompanionAPI.handle($0) }
        if prefs.companionEnabled { CompanionServer.shared.start() }

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
            startSubscriptionTimer()
        }
    }

    func setCompanionEnabled(_ enabled: Bool) {
        prefs.companionEnabled = enabled
        if enabled { CompanionServer.shared.start() } else { CompanionServer.shared.stop() }
    }

    /// Looks up a link's details (used by the iPhone app).
    func lookUp(_ link: String) async -> PreviewState {
        await fetchInfo(url: link, playlist: false)
    }

    func setSyncEnabled(_ enabled: Bool) {
        prefs.iCloudSync = enabled
        sync.configure(enabled: enabled, model: self)
    }

    // MARK: - Composer

    var trimmedURL: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValidURL: Bool { Self.isWebLink(trimmedURL) }

    static func isWebLink(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
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

    /// The channel or playlist this link belongs to, if it can be subscribed to.
    var subscribableLink: String? {
        guard let info = previewInfo else { return nil }
        if info.isPlaylist { return trimmedURL }
        return info.channelURL
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

    private func baseFetchArguments() async -> [String] {
        var args = ["--no-warnings", "--socket-timeout", "20"]
        if toolchain.impersonationAvailable { args += ["--impersonate", "chrome"] }
        args += await cookieArguments(for: prefs.baseOptions)
        return args
    }

    private func fetchInfo(url: String, playlist: Bool) async -> PreviewState {
        guard let tool = toolchain.ytdlp else { return .failed("yt-dlp isn’t installed.") }
        var args = ["-J", "--flat-playlist", playlist ? "--yes-playlist" : "--no-playlist"]
        args += await baseFetchArguments()
        args += ["--", url]
        do {
            let output = try await ProcessRunner.run(tool, args)
            if Task.isCancelled { return .empty }
            if output.status == 0, let info = MediaInfo.parse(output.stdout) {
                return .loaded(info)
            }
            return .failed(Self.describeFetchError(output.stderr))
        } catch {
            return .failed("Couldn’t load details for this link.")
        }
    }

    private static func describeFetchError(_ stderr: String) -> String {
        let error = stderr.split(separator: "\n").last { $0.contains("ERROR") }.map(String.init) ?? ""
        if error.localizedCaseInsensitiveContains("unsupported url") { return "This site isn’t supported." }
        if error.localizedCaseInsensitiveContains("sign in") || error.localizedCaseInsensitiveContains("private")
            || error.localizedCaseInsensitiveContains("logged-in") {
            return "This needs you to be signed in."
        }
        if error.localizedCaseInsensitiveContains("unavailable") || error.localizedCaseInsensitiveContains("does not exist") {
            return "This video is unavailable."
        }
        return "Couldn’t load details for this link."
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

    @discardableResult
    func enqueue(url: String, options: DownloadOptions, info: MediaInfo?, tags: MusicTags) -> DownloadJob {
        let job = DownloadJob(url: url, options: options, info: info, tags: tags)
        jobs.append(job)
        if prefs.notificationsEnabled { Notifier.requestAuthorization() }
        if info == nil { fillInDetails(for: job) }
        processQueue()
        return job
    }

    /// Links queued from the Share menu, Services or Shortcuts arrive without a preview —
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

    /// Starts queued downloads until the simultaneous-download limit is reached.
    func processQueue() {
        defer { updateDock() }
        var slots = prefs.maxConcurrent - activeJobs.count - starting.count
        for job in jobs where job.phase == .queued && !starting.contains(job.id) {
            guard slots > 0 else { break }
            slots -= 1
            starting.insert(job.id)
            Task { [weak self] in
                guard let self else { return }
                let cookies = await self.cookieArguments(for: job.options)
                self.starting.remove(job.id)
                // It may have been paused or cancelled while cookies were being prepared.
                guard job.phase == .queued else {
                    self.processQueue()
                    return
                }
                job.start(toolchain: self.toolchain, cookieArguments: cookies,
                          log: { [weak self] line in
                              self?.appendLog(line)
                              self?.updateDock()
                          },
                          completion: { [weak self] in
                              self?.jobFinished(job)
                          })
                self.updateDock()
            }
        }
    }

    private func jobFinished(_ job: DownloadJob) {
        appendLog("")
        switch job.phase {
        case .finished:
            recordHistory(for: job)
            if let subID = job.subscriptionID, let entryID = job.feedEntryID {
                subscriptions.update(subID) { $0.downloadedIDs.append(entryID) }
            }
            if job.options.isAudio && (job.options.addToMusic || job.options.fetchLyrics
                                       || job.options.embedArtwork || job.options.normalizeVolume) {
                Task { await finishAudio(job) }
            }
            if job.subscriptionID == nil {
                Notifier.post(title: job.savedFiles.count > 1 ? "Playlist Downloaded" : "Download Complete",
                              body: job.displayTitle, enabled: prefs.notificationsEnabled)
            }
        case .failed:
            Notifier.post(title: "Download Failed",
                          body: "\(job.displayTitle) — \(job.errorMessage ?? "")", enabled: prefs.notificationsEnabled)
        default:
            break
        }
        processQueue()
    }

    func pause(_ job: DownloadJob) {
        job.pause()
        updateDock()
    }

    func resume(_ job: DownloadJob) {
        job.resume()
        processQueue()
    }

    func pauseAll() {
        for job in jobs where job.isActive || job.phase == .queued { job.pause() }
        updateDock()
    }

    func resumeAll() {
        for job in jobs where job.phase == .paused { job.resume() }
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
        jobs.append(job)
        processQueue()
    }

    func remove(_ job: DownloadJob) {
        if job.isActive || job.isWaiting { job.cancel() }
        jobs.removeAll { $0.id == job.id }
        updateDock()
        processQueue()
    }

    var upNext: [DownloadJob] { jobs.filter(\.isWaiting) }

    /// Reorders waiting downloads (offsets refer to the `upNext` list).
    func moveUpNext(from source: IndexSet, to destination: Int) {
        let waiting = upNext
        let moving = source.map { waiting[$0] }
        var remaining = waiting.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = min(destination - source.filter { $0 < destination }.count, remaining.count)
        remaining.insert(contentsOf: moving, at: max(insertAt, 0))
        jobs = jobs.filter { !$0.isWaiting } + remaining
    }

    func clearFinished() {
        jobs.removeAll { $0.isDone }
    }

    func cancelAll() {
        for job in jobs where job.isActive || job.isWaiting { job.cancel() }
        for conversion in conversions where conversion.phase == .converting || conversion.phase == .waiting {
            conversion.cancel()
        }
        updateDock()
    }

    // MARK: - History, lyrics & Apple Music

    private func recordHistory(for job: DownloadJob) {
        guard !job.savedFiles.isEmpty else { return }
        let size = job.savedFiles.reduce(Int64(0)) { $0 + DownloadJob.fileSize($1) }
        // A quality upgrade replaces the old entry, and the old file if it had another name.
        if let oldID = job.replacesHistoryID, let old = history.item(id: oldID) {
            let newPaths = Set(job.savedFiles.map(\.path))
            for file in old.fileURLs where !newPaths.contains(file.path) {
                try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
            }
            history.remove(ids: [oldID])
        }
        history.add(HistoryItem(title: job.displayTitle,
                                uploader: job.info?.uploader,
                                sourceURL: job.url,
                                thumbnailURL: job.info?.thumbnailURL,
                                filePaths: job.savedFiles.map(\.path),
                                date: Date(),
                                isAudio: job.options.isAudio,
                                isPlaylist: job.savedFiles.count > 1,
                                duration: job.options.clip.map { $0.upperBound - $0.lowerBound } ?? job.info?.duration,
                                byteCount: size,
                                deviceName: Self.deviceName,
                                mediaID: LinkIdentity.mediaKey(site: job.info?.site, id: job.info?.id),
                                subscriptionID: job.subscriptionID,
                                quality: job.options.quality))
    }

    /// Finds lyrics, writes them into each song, and adds the songs to Apple Music.
    private func finishAudio(_ job: DownloadJob) async {
        if job.options.normalizeVolume, let ffmpeg = toolchain.ffmpeg {
            job.musicState = .evening
            for file in job.savedFiles where await AudioTools.normalize(file, ffmpeg: ffmpeg) {
                appendLog("Evened out volume: \(file.lastPathComponent)")
            }
            job.musicState = .none
        }
        let files = job.savedFiles.filter(MusicLibrary.canImport)
        guard !files.isEmpty else {
            if job.options.addToMusic, let first = job.savedFiles.first {
                job.musicState = .failed("Apple Music can’t import .\(first.pathExtension) files.")
            }
            return
        }
        var lyricsFound = 0
        do {
            for file in files {
                // Single songs use the (editable) tags; playlist tracks read their own.
                var tags = job.tags
                if files.count > 1 {
                    let embedded = if let ffprobe = toolchain.ffprobe {
                        await MediaTags.read(file, ffprobe: ffprobe)
                    } else {
                        MusicTags(title: file.deletingPathExtension().lastPathComponent)
                    }
                    let guess = MediaInfo(id: "", title: embedded.title, uploader: embedded.artist, duration: nil,
                                          thumbnailURL: nil, webpageURL: nil, site: nil, isPlaylist: false,
                                          playlistCount: nil, track: nil, artist: nil, album: nil,
                                          isLive: false, channelURL: nil).suggestedTags
                    tags = MusicTags(title: guess.title, artist: guess.artist, album: job.tags.album)
                }

                var lyrics: String?
                if job.options.fetchLyrics {
                    job.musicState = .findingLyrics
                    let duration = files.count == 1 ? job.info?.duration : nil
                    lyrics = await Lyrics.find(title: tags.title, artist: tags.artist, duration: duration)
                }
                // Write the tidy song details (and any lyrics) into the file itself, so it
                // looks right in every player — not just once it's in Apple Music.
                if let ffmpeg = toolchain.ffmpeg, job.options.embedArtwork || lyrics != nil {
                    if await MediaTags.write(file, tags: job.options.embedArtwork ? tags : nil,
                                             lyrics: lyrics, ffmpeg: ffmpeg), lyrics != nil {
                        lyricsFound += 1
                        appendLog("Added lyrics: \(file.lastPathComponent)")
                    }
                }
                if job.options.addToMusic {
                    job.musicState = .adding
                    try await MusicLibrary.add(file, tags: tags, lyrics: lyrics)
                    appendLog("Added to Apple Music: \(file.lastPathComponent)")
                }
            }
            job.lyricsCount = lyricsFound
            job.musicState = job.options.addToMusic ? .added : .none
        } catch {
            job.lyricsCount = lyricsFound
            job.musicState = .failed(error.localizedDescription)
            showMusicError(error)
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

    /// Downloads the best version available and replaces the existing file with it.
    func upgradeToBestQuality(_ item: HistoryItem) {
        var options = prefs.baseOptions
        options.quality = .best
        options.downloadPlaylist = item.isPlaylist
        options.forceOverwrite = true
        if let first = item.primaryFile {
            // Save next to the original, wherever it was organized.
            options.destinationPath = item.isPlaylist
                ? first.deletingLastPathComponent().deletingLastPathComponent().path
                : first.deletingLastPathComponent().path
            options.organize = .none
            options.subfolder = nil
        }
        let info = MediaInfo(id: "", title: item.title, uploader: item.uploader, duration: item.duration,
                             thumbnailURL: item.thumbnailURL, webpageURL: item.sourceURL, site: nil,
                             isPlaylist: item.isPlaylist, playlistCount: nil, track: nil, artist: nil,
                             album: nil, isLive: false, channelURL: nil)
        let job = enqueue(url: item.sourceURL, options: options, info: info, tags: MusicTags())
        job.replacesHistoryID = item.id
        selection = .queue
    }

    /// A previous download of the same video, if there is one.
    func existingDownload(link: String, info: MediaInfo?) -> HistoryItem? {
        let mediaKey = LinkIdentity.mediaKey(site: info?.site, id: info?.id)
        let linkKey = LinkIdentity.key(for: link)
        return history.items.first { item in
            guard item.cleanedUpAt == nil else { return false }
            if let mediaKey, item.mediaID == mediaKey { return true }
            return linkKey != nil && LinkIdentity.key(for: item.sourceURL) == linkKey
        }
    }

    /// Records that files were opened from My Videos (for Storage and Smart Cleanup).
    func markPlayed(_ files: [URL]) {
        let paths = Set(files.map(\.path))
        for item in history.items where item.filePaths.contains(where: paths.contains) {
            history.update(item.id) { $0.lastPlayedAt = Date() }
        }
    }

    func redownload(_ item: HistoryItem) {
        var options = prefs.baseOptions
        options.quality = item.isAudio ? .audio : (prefs.quality == .audio ? .best : prefs.quality)
        options.downloadPlaylist = item.isPlaylist
        enqueue(url: item.sourceURL, options: options, info: nil, tags: MusicTags())
        selection = .queue
    }

    // MARK: - Subscriptions

    enum FeedResult {
        case success(Feed)
        case failure(String)
    }

    func fetchFeed(_ link: String) async -> FeedResult {
        guard let tool = toolchain.ytdlp else { return .failure("yt-dlp isn’t installed.") }
        var url = FeedParser.normalize(link)
        // Playlists list oldest first, so their newest additions are at the end;
        // channel upload tabs are newest first.
        let isPlaylist = URLComponents(string: url)?.path == "/playlist"
            || (URLComponents(string: url)?.queryItems?.contains { $0.name == "list" } ?? false)
        for _ in 0..<2 {
            var args = ["-J", "--flat-playlist", "--yes-playlist", "--playlist-items", isPlaylist ? "-15:" : "1:15"]
            args += await baseFetchArguments()
            args += ["--", url]
            guard let output = try? await ProcessRunner.run(tool, args) else {
                return .failure("Couldn’t check this channel.")
            }
            guard output.status == 0, let feed = FeedParser.parse(output.stdout) else {
                return .failure(Self.describeFetchError(output.stderr))
            }
            if let tab = feed.videosTabURL {
                url = tab
                continue
            }
            if feed.entries.isEmpty { return .failure("This doesn’t look like a channel or playlist with videos.") }
            var newestFirst = feed
            if isPlaylist { newestFirst.entries.reverse() }
            return .success(newestFirst)
        }
        return .failure("Couldn’t find this channel’s videos.")
    }

    /// Adds a subscription. Existing uploads are marked as seen; optionally the newest few download now.
    func subscribe(link: String, feed: Feed, isAudio: Bool, quality: DownloadQuality,
                   addToMusic: Bool, downloadLatest: Int) {
        var sub = Subscription(url: FeedParser.normalize(link), title: feed.title, avatarURL: feed.avatarURL,
                               isAudio: isAudio, quality: quality, addToMusic: addToMusic)
        sub.seenIDs = feed.entries.map(\.id)
        sub.recent = Array(feed.entries.prefix(12))
        sub.lastChecked = Date()
        subscriptions.add(sub)
        for entry in feed.entries.prefix(downloadLatest).reversed() {
            download(entry, from: sub)
        }
        selection = .subscription(sub.id)
    }

    func unsubscribe(_ id: UUID) {
        if case .subscription(id) = selection { selection = .subscriptions }
        subscriptions.remove(id)
    }

    /// Downloads one upload from a subscription with its format settings.
    func download(_ entry: FeedEntry, from sub: Subscription) {
        let info = MediaInfo(id: entry.id, title: entry.title, uploader: sub.title, duration: entry.duration,
                             thumbnailURL: entry.thumbnailURL, webpageURL: entry.url, site: nil,
                             isPlaylist: false, playlistCount: nil, track: nil, artist: nil, album: nil,
                             isLive: false, channelURL: sub.url)
        let job = enqueue(url: entry.url, options: sub.options(from: prefs.baseOptions), info: info, tags: info.suggestedTags)
        job.subscriptionID = sub.id
        job.feedEntryID = entry.id
    }

    func checkSubscription(_ id: UUID) async {
        guard let sub = subscriptions.subscription(id: id), !checkingSubscriptions.contains(id) else { return }
        checkingSubscriptions.insert(id)
        defer { checkingSubscriptions.remove(id) }

        switch await fetchFeed(sub.url) {
        case .failure(let message):
            subscriptions.update(id) {
                $0.lastChecked = Date()
                $0.lastError = message
            }
        case .success(let feed):
            // Re-read: it may have changed (or synced) while the feed was loading.
            guard let current = subscriptions.subscription(id: id) else { return }
            // While paused, only refresh what's shown — new uploads stay "unseen" so they
            // still download once the subscription is turned back on.
            let fresh = current.isEnabled ? FeedParser.newEntries(in: feed, seen: current.seenIDs) : []
            subscriptions.update(id) {
                $0.lastChecked = Date()
                $0.lastError = nil
                $0.recent = Array(feed.entries.prefix(12))
                if let avatar = feed.avatarURL { $0.avatarURL = avatar }
                $0.seenIDs += fresh.map(\.id)
                $0.unseenCount += fresh.count
            }
            if !fresh.isEmpty {
                for entry in fresh { download(entry, from: current) }
                Notifier.post(title: current.title,
                              body: fresh.count == 1 ? "New: \(fresh[0].title)" : "\(fresh.count) new uploads are downloading.",
                              enabled: prefs.notificationsEnabled)
            }
        }
    }

    /// Whether automatic subscription downloads may run right now (download hours, network).
    var subscriptionsMayRun: Bool {
        if prefs.avoidMeteredNetworks && NetworkMonitor.shared.isMetered { return false }
        if prefs.subscriptionsOnlyAtNight {
            let hour = Calendar.current.component(.hour, from: Date())
            return QuietHours.contains(hour: hour, start: prefs.quietStartHour, end: prefs.quietEndHour)
        }
        return true
    }

    func checkAllSubscriptions(onlyDue: Bool) async {
        // Scheduled checks respect download hours; "Check Now" always runs.
        if onlyDue && !subscriptionsMayRun { return }
        let interval = TimeInterval(prefs.subscriptionInterval * 60)
        for sub in subscriptions.items where sub.isEnabled {
            if onlyDue, let last = sub.lastChecked, Date().timeIntervalSince(last) < interval { continue }
            await checkSubscription(sub.id)
        }
    }

    private func startSubscriptionTimer() {
        subscriptionTimer?.cancel()
        subscriptionTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.toolchain.isReady { await self.checkAllSubscriptions(onlyDue: true) }
                self.runSmartCleanupIfDue()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private var lastCleanup = Date.distantPast

    /// Moves watched subscription downloads to the Trash once they're old enough.
    private func runSmartCleanupIfDue() {
        guard prefs.cleanupAfterDays > 0, Date().timeIntervalSince(lastCleanup) > 3600 else { return }
        lastCleanup = Date()
        let cutoff = Date().addingTimeInterval(-Double(prefs.cleanupAfterDays) * 86400)
        for item in history.items where item.subscriptionID != nil && item.cleanedUpAt == nil {
            let files = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !files.isEmpty else { continue }
            // Only things that were actually watched — never unwatched uploads.
            let watched = ([item.lastPlayedAt] + files.map(Playback.lastOpened)).compactMap { $0 }
                .filter { $0 > item.date }.max()
            guard let watched, watched < cutoff else { continue }
            for file in files { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
            history.update(item.id) { $0.cleanedUpAt = Date() }
            appendLog("Smart Cleanup moved “\(item.title)” to the Trash.")
        }
    }

    func markViewed(_ id: UUID) {
        guard subscriptions.subscription(id: id)?.unseenCount ?? 0 > 0 else { return }
        subscriptions.update(id) { $0.unseenCount = 0 }
    }

    // MARK: - Conversions

    func convert(_ files: [URL], preset: ConvertPreset) {
        for file in files {
            conversions.append(ConvertJob(input: file, preset: preset))
        }
        stagedFiles.removeAll { files.contains($0) }
        processConversions()
    }

    /// Files dropped on the Dock icon or opened with My Videos wait here for a format choice.
    func stage(_ files: [URL]) {
        stagedFiles = Array(NSOrderedSet(array: stagedFiles + files)) as? [URL] ?? files
        selection = .convert
    }

    func removeConversion(_ job: ConvertJob) {
        job.cancel()
        conversions.removeAll { $0.id == job.id }
        processConversions()
    }

    func clearFinishedConversions() {
        conversions.removeAll { $0.phase == .finished || $0.phase == .failed || $0.phase == .cancelled }
    }

    private func processConversions() {
        guard runningConversion == nil,
              let next = conversions.first(where: { $0.phase == .waiting }) else { return }
        guard let ffmpeg = toolchain.ffmpeg else {
            for job in conversions where job.phase == .waiting {
                job.fail("ffmpeg isn’t installed. Install it in Settings → Components.")
            }
            alert = AppAlert(title: "ffmpeg Isn’t Installed", message: "Install it in Settings → Components to convert files.")
            return
        }
        appendLog("$ ffmpeg (\(next.preset.title)) \(next.input.lastPathComponent)")
        runningConversion = next
        next.start(ffmpeg: ffmpeg, ffprobe: toolchain.ffprobe) { [weak self] in
            guard let self else { return }
            self.runningConversion = nil
            if next.phase == .finished {
                Notifier.post(title: "Conversion Complete", body: next.output?.lastPathComponent ?? "",
                              enabled: self.prefs.notificationsEnabled)
            }
            self.processConversions()
        }
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
            // Read once and reused, so the browser's Keychain item isn't unlocked on every download.
            if let file = await signIn.browserCookiesForDownload(prefs: prefs, toolchain: toolchain) {
                return ["--cookies", file.path]
            }
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
        let pasteboard = NSPasteboard.general
        paste(pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string))
        return isValidURL
    }

    // MARK: - Incoming links (URL scheme, Services, Share extension, Shortcuts)

    /// myvideos://download?url=<link>[&format=audio]
    func handleIncoming(_ url: URL) {
        guard url.scheme == "myvideos",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let link = items.first(where: { $0.name == "url" })?.value else { return }
        let audio = items.first(where: { $0.name == "format" })?.value == "audio"
        downloadImmediately(link, audioOnly: audio ? true : nil)
    }

    /// Queues a link with the current defaults and brings the queue forward.
    @discardableResult
    func downloadImmediately(_ link: String, audioOnly: Bool? = nil, showQueue: Bool = true) -> DownloadJob? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isWebLink(trimmed) else { return nil }
        var options = prefs.baseOptions
        options.downloadPlaylist = false
        if let audioOnly {
            options.quality = audioOnly ? .audio : (prefs.quality == .audio ? .best : prefs.quality)
        }
        let job = enqueue(url: trimmed, options: options, info: nil, tags: MusicTags())
        if showQueue { selection = .queue }
        return job
    }

    // MARK: - Log & Dock

    func appendLog(_ line: String) {
        activityLog += line + "\n"
        // The whole log is rendered in one Text view; keep it light.
        if activityLog.utf8.count > 80_000 { activityLog = String(activityLog.suffix(60_000)) }
    }

    func log(_ line: String) { appendLog(line) }

    func updateDock() {
        DockProgress.shared.update(jobs: activeJobs, badgeCount: pendingCount)
    }
}

// MARK: - Notifications

enum Notifier {
    private static var asked = false

    /// Uses the async API: the callback form reports back on a background thread, which
    /// would crash a main-actor closure the moment the user answers the permission prompt.
    static func requestAuthorization() {
        guard !asked else { return }
        asked = true
        Task.detached(priority: .utility) {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
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
        guard AppModel.isWebLink(link) else {
            error.pointee = "The selection isn’t a web link." as NSString
            return
        }
        AppModel.shared.downloadImmediately(link)
        NSApp.activate()
    }
}
