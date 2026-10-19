//
//  Toolchain.swift
//  My Videos
//

import Foundation
import Observation

/// Finds, versions, installs and updates the command-line tools My Videos is built on.
@Observable
final class Toolchain {
    enum Operation: Equatable {
        case installing, updating
    }

    // Locations
    private(set) var ytdlp: URL?
    private(set) var ffmpeg: URL?
    private(set) var brew: URL?

    // Versions
    private(set) var ytdlpVersion: String?
    private(set) var ffmpegVersion: String?
    private(set) var latestYtdlpVersion: String?
    private(set) var impersonationAvailable = false

    // State
    private(set) var hasChecked = false
    private(set) var isCheckingForUpdates = false
    private(set) var operation: Operation?
    private(set) var operationError: String?
    private(set) var lastOperationSucceeded = false

    /// ffprobe ships alongside ffmpeg.
    var ffprobe: URL? {
        guard let dir = ffmpeg?.deletingLastPathComponent() else { return nil }
        let url = dir.appendingPathComponent("ffprobe")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    var isReady: Bool { ytdlp != nil && ffmpeg != nil }
    var missingTools: [String] {
        [ytdlp == nil ? "yt-dlp" : nil, ffmpeg == nil ? "ffmpeg" : nil].compactMap { $0 }
    }

    var updateAvailable: Bool {
        guard let installed = ytdlpVersion, let latest = latestYtdlpVersion else { return false }
        return Self.isVersion(latest, newerThan: installed)
    }

    /// Homebrew-managed tools must be updated through brew (yt-dlp -U refuses).
    var isHomebrewManaged: Bool {
        ytdlp?.resolvingSymlinksInPath().path.contains("/Cellar/") ?? false
    }

    // MARK: - Environment

    /// GUI apps don't inherit the shell's PATH, so look in the usual install locations.
    nonisolated static let searchDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
        NSHomeDirectory() + "/.local/bin",
    ]

    nonisolated static var childEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchDirectories + ["/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        return env
    }

    nonisolated static func locate(_ tool: String) -> URL? {
        for dir in searchDirectories {
            let path = dir + "/" + tool
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    // MARK: - Discovery

    /// Re-locates the tools and reads their versions. Cheap enough to call any time.
    func refresh() async {
        ytdlp = Self.locate("yt-dlp")
        ffmpeg = Self.locate("ffmpeg")
        brew = Self.locate("brew")

        async let ytVersion = Self.version(of: ytdlp, arguments: ["--version"]) { $0 }
        async let ffVersion = Self.version(of: ffmpeg, arguments: ["-version"]) { output in
            // "ffmpeg version 8.0 Copyright (c) …"
            output.split(separator: " ").dropFirst(2).first.map(String.init)
        }
        async let impersonation = Self.checkImpersonation(tool: ytdlp)
        ytdlpVersion = await ytVersion
        ffmpegVersion = await ffVersion
        impersonationAvailable = await impersonation
        hasChecked = true
    }

    nonisolated private static func version(of tool: URL?, arguments: [String],
                                            parse: @Sendable (String) -> String?) async -> String? {
        guard let tool, let output = try? await ProcessRunner.run(tool, arguments), output.status == 0 else { return nil }
        let firstLine = output.stdoutText.split(separator: "\n").first.map(String.init) ?? ""
        return parse(firstLine.trimmingCharacters(in: .whitespaces))
    }

    nonisolated private static func checkImpersonation(tool: URL?) async -> Bool {
        guard let tool, let output = try? await ProcessRunner.run(tool, ["--list-impersonate-targets"]) else { return false }
        // Without curl_cffi, yt-dlp still lists every target but marks them
        // "(unavailable)" — only count a Chrome target that's actually usable.
        return output.stdoutText.lowercased().split(separator: "\n").contains {
            $0.contains("chrome") && $0.contains("curl_cffi") && !$0.contains("unavailable")
        }
    }

    // MARK: - Updates

    /// Asks GitHub for the newest yt-dlp release. Sites change constantly, and an
    /// out-of-date yt-dlp is the #1 reason downloads suddenly start failing.
    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return }
        latestYtdlpVersion = tag
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
    }

    static var lastUpdateCheck: Date? {
        UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
    }

    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Updates yt-dlp the way it was installed. Output lines go to `log`.
    func updateYtdlp(log: @escaping @MainActor (String) -> Void) async {
        guard operation == nil, let ytdlp else { return }
        if isHomebrewManaged, let brew {
            await perform(.updating, tool: brew, arguments: ["upgrade", "yt-dlp"], log: log)
        } else {
            await perform(.updating, tool: ytdlp, arguments: ["-U"], log: log)
        }
    }

    /// Installs whatever is missing with Homebrew.
    func installMissing(log: @escaping @MainActor (String) -> Void) async {
        guard operation == nil, let brew, !missingTools.isEmpty else { return }
        await perform(.installing, tool: brew, arguments: ["install"] + missingTools, log: log)
    }

    private func perform(_ op: Operation, tool: URL, arguments: [String],
                         log: @escaping @MainActor (String) -> Void) async {
        operation = op
        operationError = nil
        lastOperationSucceeded = false
        log("$ \(tool.lastPathComponent) \(arguments.joined(separator: " "))")

        let status: Int32 = await withCheckedContinuation { continuation in
            let process = StreamingProcess(executable: tool, arguments: arguments)
            do {
                try process.start(onLines: { lines in
                    lines.forEach(log)
                }, onExit: { status, _ in
                    continuation.resume(returning: status)
                })
            } catch {
                log("Couldn’t launch \(tool.lastPathComponent): \(error.localizedDescription)")
                continuation.resume(returning: -1)
            }
        }

        await refresh()
        operation = nil
        if status == 0 {
            lastOperationSucceeded = true
            if op == .updating, let latest = latestYtdlpVersion, let now = ytdlpVersion,
               Self.isVersion(latest, newerThan: now) {
                operationError = "Homebrew doesn’t have yt-dlp \(latest) yet. It usually arrives within a day — try again later."
                lastOperationSucceeded = false
            }
        } else {
            operationError = op == .installing
                ? "Installation didn’t finish. Open the activity log for details."
                : "The update didn’t finish. Open the activity log for details."
        }
        log("")
    }
}
