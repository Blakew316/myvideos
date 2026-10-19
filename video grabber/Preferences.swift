//
//  Preferences.swift
//  My Videos
//

import Foundation
import Observation

/// Persisted user choices. Download controls remember what was used last.
/// Download-related settings also sync between Macs through iCloud Drive.
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    // Synced download settings
    var quality: DownloadQuality { didSet { save(quality.rawValue, Keys.quality, synced: true) } }
    var audioFormat: AudioFormat { didSet { save(audioFormat.rawValue, Keys.audioFormat, synced: true) } }
    var audioBitrate: AudioBitrate { didSet { save(audioBitrate.rawValue, Keys.audioBitrate, synced: true) } }
    var subtitles: SubtitleMode { didSet { save(subtitles.rawValue, Keys.subtitles, synced: true) } }
    var subtitleLanguage: SubtitleLanguage { didSet { save(subtitleLanguage.rawValue, Keys.subtitleLanguage, synced: true) } }
    var embedArtwork: Bool { didSet { save(embedArtwork, Keys.embedArtwork, synced: true) } }
    var addToMusic: Bool { didSet { save(addToMusic, Keys.addToMusic, synced: true) } }
    var fetchLyrics: Bool { didSet { save(fetchLyrics, Keys.fetchLyrics, synced: true) } }
    var sponsorBlock: SponsorBlockMode { didSet { save(sponsorBlock.rawValue, Keys.sponsorBlock, synced: true) } }
    var organize: OrganizeMode { didSet { save(organize.rawValue, Keys.organize, synced: true) } }
    var speedLimit: SpeedLimit { didSet { save(speedLimit.rawValue, Keys.speedLimit, synced: true) } }
    var maxConcurrent: Int {
        didSet {
            save(maxConcurrent, Keys.maxConcurrent, synced: true)
            // More slots: start waiting downloads now rather than when one finishes.
            Task { @MainActor in AppModel.shared.processQueue() }
        }
    }
    /// Minutes between subscription checks.
    var subscriptionInterval: Int { didSet { save(subscriptionInterval, Keys.subscriptionInterval, synced: true) } }

    // This Mac only
    var destination: URL { didSet { save(destination.path, Keys.destination) } }
    var cookieSource: CookieSource { didSet { save(cookieSource.rawValue, Keys.cookieSource) } }
    var cookieBrowser: CookieBrowser { didSet { save(cookieBrowser.rawValue, Keys.cookieBrowser) } }
    var cookieFilePath: String { didSet { save(cookieFilePath, Keys.cookieFile) } }
    /// A specific browser profile ("Profile 4"); empty means the most recently used one.
    var cookieBrowserProfile: String { didSet { save(cookieBrowserProfile, Keys.cookieProfile) } }
    var notificationsEnabled: Bool { didSet { save(notificationsEnabled, Keys.notifications) } }
    var clipboardDetection: Bool { didSet { save(clipboardDetection, Keys.clipboard) } }
    var showMenuBarExtra: Bool { didSet { save(showMenuBarExtra, Keys.menuBar) } }
    var autoCheckUpdates: Bool { didSet { save(autoCheckUpdates, Keys.autoUpdate) } }
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, Keys.onboarding) } }
    var iCloudSync: Bool { didSet { save(iCloudSync, Keys.iCloudSync) } }
    var normalizeVolume: Bool { didSet { save(normalizeVolume, Keys.normalizeVolume) } }
    /// Subscriptions only download between these hours (e.g. overnight).
    var subscriptionsOnlyAtNight: Bool { didSet { save(subscriptionsOnlyAtNight, Keys.onlyAtNight) } }
    var quietStartHour: Int { didSet { save(quietStartHour, Keys.quietStart) } }
    var quietEndHour: Int { didSet { save(quietEndHour, Keys.quietEnd) } }
    /// Skip subscription downloads on a phone hotspot or other metered connection.
    var avoidMeteredNetworks: Bool { didSet { save(avoidMeteredNetworks, Keys.avoidMetered) } }
    /// Days after watching that subscription downloads move to the Trash (0 = never).
    var cleanupAfterDays: Int { didSet { save(cleanupAfterDays, Keys.cleanupDays) } }
    /// Lets the iPhone app connect over the local network.
    var companionEnabled: Bool { didSet { save(companionEnabled, Keys.companion) } }
    /// Downloads show up in Spotlight searches.
    var spotlightEnabled: Bool {
        didSet {
            save(spotlightEnabled, Keys.spotlight)
            Task { @MainActor in SpotlightIndex.schedule(AppModel.shared.history.items, enabled: spotlightEnabled) }
        }
    }

    /// When a synced setting last changed here; the newer side wins when syncing.
    private(set) var syncedSettingsModified: Date
    private var applyingRemote = false

    private enum Keys {
        static let destination = "destinationPath"
        static let quality = "quality"
        static let audioFormat = "audioFormat"
        static let audioBitrate = "audioBitrate"
        static let cookieSource = "cookieSource"
        static let cookieBrowser = "cookieBrowser"
        static let cookieFile = "cookieFilePath"
        static let cookieProfile = "cookieBrowserProfile"
        static let subtitles = "subtitles"
        static let subtitleLanguage = "subtitleLanguage"
        static let embedArtwork = "embedArtwork"
        static let addToMusic = "addToMusic"
        static let fetchLyrics = "fetchLyrics"
        static let sponsorBlock = "sponsorBlock"
        static let organize = "organize"
        static let speedLimit = "speedLimit"
        static let maxConcurrent = "maxConcurrent"
        static let subscriptionInterval = "subscriptionInterval"
        static let notifications = "notificationsEnabled"
        static let clipboard = "clipboardDetection"
        static let menuBar = "showMenuBarExtra"
        static let autoUpdate = "autoCheckUpdates"
        static let onboarding = "hasCompletedOnboarding"
        static let iCloudSync = "iCloudSync"
        static let normalizeVolume = "normalizeVolume"
        static let onlyAtNight = "subscriptionsOnlyAtNight"
        static let quietStart = "quietStartHour"
        static let quietEnd = "quietEndHour"
        static let avoidMetered = "avoidMeteredNetworks"
        static let cleanupDays = "cleanupAfterDays"
        static let companion = "companionEnabled"
        static let spotlight = "spotlightEnabled"
        static let syncedModified = "syncedSettingsModified"
    }

    init() {
        let d = UserDefaults.standard
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            d.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        func int(_ key: String, _ fallback: Int) -> Int {
            d.object(forKey: key) == nil ? fallback : d.integer(forKey: key)
        }

        quality = value(Keys.quality, .best)
        audioFormat = value(Keys.audioFormat, .m4a)
        audioBitrate = value(Keys.audioBitrate, .best)
        subtitles = value(Keys.subtitles, .off)
        subtitleLanguage = value(Keys.subtitleLanguage,
                                 SubtitleLanguage(rawValue: Locale.current.language.languageCode?.identifier ?? "en") ?? .en)
        embedArtwork = bool(Keys.embedArtwork, true)
        addToMusic = bool(Keys.addToMusic, true)
        fetchLyrics = bool(Keys.fetchLyrics, true)
        sponsorBlock = value(Keys.sponsorBlock, .off)
        organize = value(Keys.organize, .none)
        speedLimit = SpeedLimit(rawValue: int(Keys.speedLimit, 0)) ?? .unlimited
        maxConcurrent = min(max(int(Keys.maxConcurrent, 1), 1), 3)
        subscriptionInterval = int(Keys.subscriptionInterval, 60)

        cookieSource = value(Keys.cookieSource, .none)
        cookieBrowser = value(Keys.cookieBrowser, .chrome)
        cookieFilePath = d.string(forKey: Keys.cookieFile) ?? ""
        cookieBrowserProfile = d.string(forKey: Keys.cookieProfile) ?? ""
        notificationsEnabled = bool(Keys.notifications, true)
        clipboardDetection = bool(Keys.clipboard, true)
        showMenuBarExtra = bool(Keys.menuBar, true)
        autoCheckUpdates = bool(Keys.autoUpdate, true)
        hasCompletedOnboarding = bool(Keys.onboarding, false)
        iCloudSync = bool(Keys.iCloudSync, false)
        normalizeVolume = bool(Keys.normalizeVolume, false)
        subscriptionsOnlyAtNight = bool(Keys.onlyAtNight, false)
        quietStartHour = int(Keys.quietStart, 1)
        quietEndHour = int(Keys.quietEnd, 6)
        avoidMeteredNetworks = bool(Keys.avoidMetered, false)
        cleanupAfterDays = int(Keys.cleanupDays, 0)
        companionEnabled = bool(Keys.companion, false)
        spotlightEnabled = bool(Keys.spotlight, true)
        syncedSettingsModified = d.object(forKey: Keys.syncedModified) as? Date ?? .distantPast

        if let path = d.string(forKey: Keys.destination), FileManager.default.fileExists(atPath: path) {
            destination = URL(fileURLWithPath: path)
        } else {
            destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        }
    }

    private func save(_ value: Any, _ key: String, synced: Bool = false) {
        defaults.set(value, forKey: key)
        if synced && !applyingRemote {
            syncedSettingsModified = Date()
            defaults.set(syncedSettingsModified, forKey: Keys.syncedModified)
            NotificationCenter.default.post(name: .myVideosLocalDataChanged, object: nil)
        }
    }

    /// The options a new download starts from.
    var baseOptions: DownloadOptions {
        DownloadOptions(quality: quality, audioFormat: audioFormat, audioBitrate: audioBitrate,
                        destinationPath: destination.path,
                        subtitles: subtitles, subtitleLanguage: subtitleLanguage,
                        embedArtwork: embedArtwork, addToMusic: addToMusic,
                        cookieSource: cookieSource, cookieBrowser: cookieBrowser,
                        cookieFilePath: cookieFilePath,
                        sponsorBlock: sponsorBlock, organize: organize,
                        speedLimit: speedLimit, fetchLyrics: fetchLyrics,
                        normalizeVolume: normalizeVolume)
    }

    // MARK: - Sync

    var syncedSettings: SyncedSettings {
        SyncedSettings(modified: syncedSettingsModified, quality: quality, audioFormat: audioFormat,
                       audioBitrate: audioBitrate, subtitles: subtitles, subtitleLanguage: subtitleLanguage,
                       embedArtwork: embedArtwork, addToMusic: addToMusic, fetchLyrics: fetchLyrics,
                       sponsorBlock: sponsorBlock, organize: organize, speedLimit: speedLimit,
                       maxConcurrent: maxConcurrent, subscriptionInterval: subscriptionInterval)
    }

    func apply(_ s: SyncedSettings) {
        guard s.modified > syncedSettingsModified else { return }
        applyingRemote = true
        defer { applyingRemote = false }
        quality = s.quality
        audioFormat = s.audioFormat
        audioBitrate = s.audioBitrate
        subtitles = s.subtitles
        subtitleLanguage = s.subtitleLanguage
        embedArtwork = s.embedArtwork
        addToMusic = s.addToMusic
        fetchLyrics = s.fetchLyrics
        sponsorBlock = s.sponsorBlock
        organize = s.organize
        speedLimit = s.speedLimit
        maxConcurrent = s.maxConcurrent
        subscriptionInterval = s.subscriptionInterval
        syncedSettingsModified = s.modified
        defaults.set(s.modified, forKey: Keys.syncedModified)
    }
}

/// The download settings shared between Macs.
nonisolated struct SyncedSettings: Codable, Sendable, Equatable {
    var modified: Date
    var quality: DownloadQuality
    var audioFormat: AudioFormat
    var audioBitrate: AudioBitrate
    var subtitles: SubtitleMode
    var subtitleLanguage: SubtitleLanguage
    var embedArtwork: Bool
    var addToMusic: Bool
    var fetchLyrics: Bool
    var sponsorBlock: SponsorBlockMode
    var organize: OrganizeMode
    var speedLimit: SpeedLimit
    var maxConcurrent: Int
    var subscriptionInterval: Int
}
