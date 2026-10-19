//
//  Intents.swift
//  My Videos
//

import AppIntents
import Foundation

/// Video or audio, as offered in Shortcuts.
enum IntentFormat: String, AppEnum {
    case video, audio

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Format"
    static let caseDisplayRepresentations: [IntentFormat: DisplayRepresentation] = [
        .video: DisplayRepresentation(title: "Video", image: .init(systemName: "film")),
        .audio: DisplayRepresentation(title: "Audio Only", image: .init(systemName: "music.note")),
    ]
}

/// "Download Video" — queues a link with your usual settings.
struct DownloadVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Download Video"
    static let description = IntentDescription("Downloads a video or song from a link with My Videos, using your usual settings.",
                                               categoryName: "Downloading")

    @Parameter(title: "Link", description: "A link to a video, song or playlist page.")
    var link: URL

    @Parameter(title: "Format", default: .video)
    var format: IntentFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Download \(\.$link) as \(\.$format)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.toolchain.ytdlp != nil || Toolchain.locate("yt-dlp") != nil else {
            throw IntentError.notSetUp
        }
        if !model.toolchain.hasChecked { await model.toolchain.refresh() }
        guard let job = model.downloadImmediately(link.absoluteString, audioOnly: format == .audio, showQueue: false) else {
            throw IntentError.invalidLink
        }
        _ = job
        return .result(dialog: format == .audio ? "Downloading the audio now." : "Downloading the video now.")
    }
}

/// "Get Recent Downloads" — hands files to the next action in a shortcut.
struct RecentDownloadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Recent Downloads"
    static let description = IntentDescription("Returns the files you downloaded most recently with My Videos.",
                                               categoryName: "Library")

    @Parameter(title: "Limit", default: 5, inclusiveRange: (1, 50))
    var limit: Int

    @Parameter(title: "Kind", default: .all)
    var kind: IntentKind

    static var parameterSummary: some ParameterSummary {
        Summary("Get the \(\.$limit) most recent \(\.$kind) downloads")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let items = AppModel.shared.history.items.filter {
            switch kind {
            case .all: return true
            case .videos: return !$0.isAudio
            case .music: return $0.isAudio
            }
        }
        let files = items.flatMap(\.fileURLs)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(limit)
            .map { IntentFile(fileURL: $0) }
        return .result(value: Array(files))
    }
}

enum IntentKind: String, AppEnum {
    case all, videos, music

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kind"
    static let caseDisplayRepresentations: [IntentKind: DisplayRepresentation] = [
        .all: "All",
        .videos: "Video",
        .music: "Music",
    ]
}

/// "Check Subscriptions" — looks for new uploads right away.
struct CheckSubscriptionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Subscriptions"
    static let description = IntentDescription("Checks every subscription for new uploads and downloads them.",
                                               categoryName: "Subscriptions")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        if !model.toolchain.hasChecked { await model.toolchain.refresh() }
        let before = model.pendingCount
        await model.checkAllSubscriptions(onlyDue: false)
        let added = max(model.pendingCount - before, 0)
        return .result(dialog: added == 0 ? "No new uploads." : "Downloading \(added) new upload\(added == 1 ? "" : "s").")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidLink, notSetUp

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidLink: return "That isn’t a web link My Videos can download."
        case .notSetUp: return "Open My Videos to finish setting it up first."
        }
    }
}

/// Phrases for Siri and Spotlight, available as soon as the app is installed.
struct MyVideosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DownloadVideoIntent(),
                    phrases: ["Download a video with \(.applicationName)",
                              "Save a video with \(.applicationName)",
                              "Download with \(.applicationName)"],
                    shortTitle: "Download Video",
                    systemImageName: "arrow.down.circle")
        AppShortcut(intent: CheckSubscriptionsIntent(),
                    phrases: ["Check my \(.applicationName) subscriptions",
                              "Check for new videos in \(.applicationName)"],
                    shortTitle: "Check Subscriptions",
                    systemImageName: "dot.radiowaves.left.and.right")
        AppShortcut(intent: RecentDownloadsIntent(),
                    phrases: ["Get my recent downloads from \(.applicationName)"],
                    shortTitle: "Recent Downloads",
                    systemImageName: "clock")
    }
}
