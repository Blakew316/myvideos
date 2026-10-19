//
//  Updater.swift
//  My Videos
//

import Foundation
import Observation
import Sparkle

/// Automatic app updates through Sparkle. Stays dormant until a release feed and signing
/// key are set in Info.plist (SUFeedURL / SUPublicEDKey) — see scripts/release.sh.
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController?
    private(set) var canCheckForUpdates = false
    private var observation: NSKeyValueObservation?

    var isConfigured: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !feed.isEmpty, !key.isEmpty, !AppModel.isTesting else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "1.0") (\(info["CFBundleVersion"] as? String ?? "1"))"
    }
}
