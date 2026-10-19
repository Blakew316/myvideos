//
//  Diagnostics.swift
//  My Videos
//

import AppKit
import MetricKit
import UniformTypeIdentifiers
import Observation

/// Collects crash and hang reports (via MetricKit, plus uncaught exceptions) on this Mac
/// only, and bundles them with the activity log when the user chooses to share them.
@Observable
final class Diagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = Diagnostics()

    private(set) var reports: [URL] = []
    /// A crash report arrived since the user last looked.
    private(set) var hasNewCrash = false

    nonisolated static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("My Videos/Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let seenKey = "diagnosticsLastSeen"

    func start() {
        MXMetricManager.shared.add(self)
        NSSetUncaughtExceptionHandler { exception in
            Diagnostics.writeException(exception)
        }
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder,
                                                                  includingPropertiesForKeys: [.creationDateKey])) ?? []
        reports = files.filter { $0.pathExtension == "json" || $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        let lastSeen = UserDefaults.standard.object(forKey: Self.seenKey) as? Date ?? .distantPast
        hasNewCrash = reports.contains {
            $0.lastPathComponent.hasPrefix("crash") &&
            ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > lastSeen
        }
    }

    func markSeen() {
        UserDefaults.standard.set(Date(), forKey: Self.seenKey)
        hasNewCrash = false
    }

    func deleteAll() {
        for report in reports { try? FileManager.default.removeItem(at: report) }
        reload()
    }

    // MARK: Collection

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let isCrash = !(payload.crashDiagnostics ?? []).isEmpty
            let name = "\(isCrash ? "crash" : "diagnostic")-\(Self.stamp()).json"
            try? payload.jsonRepresentation().write(to: Self.folder.appendingPathComponent(name))
        }
        Task { @MainActor in Diagnostics.shared.reload() }
    }

    nonisolated private static func writeException(_ exception: NSException) {
        let text = """
            My Videos — uncaught exception
            Date: \(Date())
            Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "none")

            \(exception.callStackSymbols.joined(separator: "\n"))
            """
        try? text.write(to: folder.appendingPathComponent("crash-\(stamp()).txt"), atomically: true, encoding: .utf8)
    }

    nonisolated private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    // MARK: Export

    /// Zips the reports, the activity log and version info, and asks where to save it.
    func exportReport(activityLog: String, toolchain: Toolchain) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "My Videos Report \(Self.stamp()).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("My Videos Report", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let info = """
            My Videos \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))
            macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            yt-dlp \(toolchain.ytdlpVersion ?? "not installed")
            ffmpeg \(toolchain.ffmpegVersion ?? "not installed")
            Browser impersonation: \(toolchain.impersonationAvailable ? "available" : "unavailable")
            """
        try? info.write(to: staging.appendingPathComponent("System.txt"), atomically: true, encoding: .utf8)
        try? activityLog.write(to: staging.appendingPathComponent("Activity Log.txt"), atomically: true, encoding: .utf8)
        for report in reports {
            try? FileManager.default.copyItem(at: report, to: staging.appendingPathComponent(report.lastPathComponent))
        }
        try? FileManager.default.removeItem(at: destination)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", staging.path, destination.path]
        try? ditto.run()
        ditto.waitUntilExit()
        try? FileManager.default.removeItem(at: staging)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
}
