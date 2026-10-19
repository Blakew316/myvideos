//
//  Preferences.swift
//  My Videos
//

import Foundation
import Observation

/// Persisted user choices. Download controls remember what was used last.
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    var quality: DownloadQuality { didSet { save(quality.rawValue, Keys.quality) } }
    var audioFormat: AudioFormat { didSet { save(audioFormat.rawValue, Keys.audioFormat) } }
    var audioBitrate: AudioBitrate { didSet { save(audioBitrate.rawValue, Keys.audioBitrate) } }
    var destination: URL { didSet { save(destination.path, Keys.destination) } }
    var subtitles: SubtitleMode { didSet { save(subtitles.rawValue, Keys.subtitles) } }
    var subtitleLanguage: SubtitleLanguage { didSet { save(subtitleLanguage.rawValue, Keys.subtitleLanguage) } }
    var embedArtwork: Bool { didSet { save(embedArtwork, Keys.embedArtwork) } }
    var addToMusic: Bool { didSet { save(addToMusic, Keys.addToMusic) } }

    var cookieSource: CookieSource { didSet { save(cookieSource.rawValue, Keys.cookieSource) } }
    var cookieBrowser: CookieBrowser { didSet { save(cookieBrowser.rawValue, Keys.cookieBrowser) } }
    var cookieFilePath: String { didSet { save(cookieFilePath, Keys.cookieFile) } }

    var notificationsEnabled: Bool { didSet { save(notificationsEnabled, Keys.notifications) } }
    var clipboardDetection: Bool { didSet { save(clipboardDetection, Keys.clipboard) } }
    var showMenuBarExtra: Bool { didSet { save(showMenuBarExtra, Keys.menuBar) } }
    var autoCheckUpdates: Bool { didSet { save(autoCheckUpdates, Keys.autoUpdate) } }
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, Keys.onboarding) } }

    private enum Keys {
        static let destination = "destinationPath"
        static let quality = "quality"
        static let audioFormat = "audioFormat"
        static let audioBitrate = "audioBitrate"
        static let cookieSource = "cookieSource"
        static let cookieBrowser = "cookieBrowser"
        static let cookieFile = "cookieFilePath"
        static let subtitles = "subtitles"
        static let subtitleLanguage = "subtitleLanguage"
        static let embedArtwork = "embedArtwork"
        static let addToMusic = "addToMusic"
        static let notifications = "notificationsEnabled"
        static let clipboard = "clipboardDetection"
        static let menuBar = "showMenuBarExtra"
        static let autoUpdate = "autoCheckUpdates"
        static let onboarding = "hasCompletedOnboarding"
    }

    init() {
        let d = UserDefaults.standard
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            d.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }

        quality = value(Keys.quality, .best)
        audioFormat = value(Keys.audioFormat, .m4a)
        audioBitrate = value(Keys.audioBitrate, .best)
        subtitles = value(Keys.subtitles, .off)
        subtitleLanguage = value(Keys.subtitleLanguage,
                                 SubtitleLanguage(rawValue: Locale.current.language.languageCode?.identifier ?? "en") ?? .en)
        cookieSource = value(Keys.cookieSource, .none)
        cookieBrowser = value(Keys.cookieBrowser, .chrome)
        cookieFilePath = d.string(forKey: Keys.cookieFile) ?? ""
        embedArtwork = bool(Keys.embedArtwork, true)
        addToMusic = bool(Keys.addToMusic, true)
        notificationsEnabled = bool(Keys.notifications, true)
        clipboardDetection = bool(Keys.clipboard, true)
        showMenuBarExtra = bool(Keys.menuBar, true)
        autoCheckUpdates = bool(Keys.autoUpdate, true)
        hasCompletedOnboarding = bool(Keys.onboarding, false)

        if let path = d.string(forKey: Keys.destination), FileManager.default.fileExists(atPath: path) {
            destination = URL(fileURLWithPath: path)
        } else {
            destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        }
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    /// The options a new download starts from.
    var baseOptions: DownloadOptions {
        DownloadOptions(quality: quality, audioFormat: audioFormat, audioBitrate: audioBitrate,
                        destinationPath: destination.path,
                        subtitles: subtitles, subtitleLanguage: subtitleLanguage,
                        embedArtwork: embedArtwork, addToMusic: addToMusic,
                        cookieSource: cookieSource, cookieBrowser: cookieBrowser,
                        cookieFilePath: cookieFilePath)
    }
}
