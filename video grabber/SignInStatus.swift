//
//  SignInStatus.swift
//  My Videos
//
//  Knows whether the chosen sign-in method actually works, and which sites it covers.
//

import AppKit
import Foundation
import Observation

/// Sign-in cookies that identify a logged-in account (by site).
nonisolated enum CookieSites {
    static let authNames: Set<String> = ["SID", "SAPISID", "__Secure-3PSID", "__Secure-1PSID", "LOGIN_INFO", "sessionid",
                                         "auth_token", "vuid", "c_user", "sid_tt", "auth-token", "sessionid_ss"]

    /// "youtube.com", "vimeo.com"… from a Netscape cookies.txt.
    static func sites(inCookieFile text: String) -> [String] {
        var sites = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            var line = String(line)
            if line.hasPrefix("#HttpOnly_") { line.removeFirst("#HttpOnly_".count) }
            guard !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 7, authNames.contains(String(fields[5])) else { continue }
            sites.insert(baseDomain(String(fields[0])))
        }
        return sites.sorted()
    }

    static func isNetscapeFile(_ text: String) -> Bool {
        if text.hasPrefix("# Netscape HTTP Cookie File") || text.hasPrefix("# HTTP Cookie File") { return true }
        return text.split(whereSeparator: \.isNewline).contains {
            !$0.hasPrefix("#") && $0.split(separator: "\t", omittingEmptySubsequences: false).count >= 7
        }
    }

    static func baseDomain(_ domain: String) -> String {
        let parts = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".")
        return parts.suffix(2).joined(separator: ".")
    }
}

/// The state of the selected sign-in method, shown under the Sign-In picker.
@Observable
final class SignInStatus {
    enum State: Equatable {
        case notNeeded
        case checking
        case ready([String])
        case problem(String, Fix)
    }

    enum Fix: Equatable {
        case none, signIn, chooseFile, fullDiskAccess, retry, useBuiltIn
    }

    /// A browser profile, e.g. ("Profile 4", "Justin — justin@example.com").
    struct Profile: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
    }

    /// Profiles of the chosen browser (empty if it has just one, or can't be read yet).
    private(set) var profiles: [Profile] = []

    private(set) var state: State = .notNeeded
    private var serial = 0

    /// Where sign-ins read from another browser are kept, so downloads don't have to
    /// unlock the browser's Keychain item every time.
    static var browserCookieFile: URL { HistoryStore.supportDirectory.appendingPathComponent("browser-cookies.txt") }
    private static let browserKey = "browserCookiesSource"
    private static let exportedKey = "browserCookiesExported"

    /// Re-checks the current method. `readBrowser` re-reads the browser even if a recent copy exists.
    func check(prefs: Preferences, toolchain: Toolchain, readBrowser: Bool = false) async {
        serial += 1
        let mine = serial
        switch prefs.cookieSource {
        case .none:
            state = .notNeeded
        case .builtIn:
            let sites = await SignInSession.signedInSites()
            guard mine == serial else { return }
            state = sites.isEmpty ? .problem("You’re not signed in to any sites yet.", .signIn) : .ready(sites)
        case .file:
            state = Self.checkFile(prefs.cookieFilePath)
        case .browser:
            let browser = prefs.cookieBrowser
            profiles = Self.profiles(of: browser)
            if !prefs.cookieBrowserProfile.isEmpty, !profiles.contains(where: { $0.id == prefs.cookieBrowserProfile }) {
                prefs.cookieBrowserProfile = ""
            }
            if let problem = Self.accessProblem(browser) {
                state = problem
                return
            }
            let spec = browser.specification(profile: prefs.cookieBrowserProfile)
            if !readBrowser, let cached = Self.cachedBrowserSites(for: spec) {
                state = cached.isEmpty ? Self.noSignIns(browser, profiles: profiles) : .ready(cached)
                return
            }
            state = .checking
            let result = await Self.exportBrowser(browser, spec: spec, profiles: profiles, toolchain: toolchain)
            guard mine == serial else { return }
            state = result
        }
    }

    static func checkFile(_ path: String) -> State {
        guard !path.isEmpty else { return .problem("Choose a cookies.txt file.", .chooseFile) }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .problem("That file can’t be found or opened. Choose it again.", .chooseFile)
        }
        guard CookieSites.isNetscapeFile(text) else {
            return .problem("That isn’t a cookies.txt file. Export one in “Netscape” format.", .chooseFile)
        }
        let sites = CookieSites.sites(inCookieFile: text)
        return sites.isEmpty ? .problem("That file has no sign-ins. Export it while you’re signed in.", .chooseFile) : .ready(sites)
    }

    private static func cachedBrowserSites(for spec: String) -> [String]? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: browserKey) == spec,
              let exported = defaults.object(forKey: exportedKey) as? Date,
              Date().timeIntervalSince(exported) < 12 * 3600,
              let text = try? String(contentsOf: browserCookieFile, encoding: .utf8) else { return nil }
        return CookieSites.sites(inCookieFile: text)
    }

    /// The cookies.txt downloads should use for the browser method, re-reading the browser if stale.
    func browserCookiesForDownload(prefs: Preferences, toolchain: Toolchain) async -> URL? {
        let spec = prefs.cookieBrowser.specification(profile: prefs.cookieBrowserProfile)
        if Self.cachedBrowserSites(for: spec) == nil {
            if let problem = Self.accessProblem(prefs.cookieBrowser) {
                state = problem
                return nil
            }
            state = .checking
            state = await Self.exportBrowser(prefs.cookieBrowser, spec: spec, profiles: profiles, toolchain: toolchain)
        }
        return FileManager.default.fileExists(atPath: Self.browserCookieFile.path) ? Self.browserCookieFile : nil
    }

    /// Installed? Readable? Checked before running yt-dlp, which can't tell "blocked by macOS"
    /// from "not there" (both look like an empty folder to it).
    static func accessProblem(_ browser: CookieBrowser) -> State? {
        if browser != .safari, NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) == nil {
            return .problem("\(browser.displayName) isn’t installed on this Mac.", .useBuiltIn)
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: browser.dataDirectory)
            return nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .problem("\(browser.displayName) hasn’t been used on this Mac yet. Open it and sign in first.", .retry)
        } catch {
            return .problem("macOS is blocking My Videos from reading \(browser.displayName)’s sign-ins. Turn on My Videos in Full Disk Access, then reopen My Videos.", .fullDiskAccess)
        }
    }

    /// Chrome-style profiles from "Local State", named the way the browser shows them.
    static func profiles(of browser: CookieBrowser) -> [Profile] {
        let fm = FileManager.default
        if browser.isChromium {
            let localState = browser.dataDirectory + "/Local State"
            guard let data = fm.contents(atPath: localState),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]] else { return [] }
            let profiles = cache.map { id, info -> Profile in
                let name = (info["name"] as? String) ?? id
                let email = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return Profile(id: id, name: email.map { "\(name) — \($0)" } ?? name)
            }
            return profiles.count > 1 ? profiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : []
        }
        if browser == .firefox {
            let dirs = (try? fm.contentsOfDirectory(atPath: browser.dataDirectory)) ?? []
            let profiles = dirs.filter { !$0.hasPrefix(".") }.sorted().map {
                Profile(id: $0, name: $0.split(separator: ".", maxSplits: 1).last.map(String.init) ?? $0)
            }
            return profiles.count > 1 ? profiles : []
        }
        return []
    }

    private static func noSignIns(_ browser: CookieBrowser, profiles: [Profile]) -> State {
        .problem(profiles.isEmpty
                 ? "No sign-ins found in \(browser.displayName). Sign in to the site there, then check again."
                 : "No sign-ins found in this \(browser.displayName) profile. Choose the profile you use for the site.",
                 .retry)
    }

    /// Asks yt-dlp to read the browser's cookies (offline) and save them as a private cookies.txt.
    private static func exportBrowser(_ browser: CookieBrowser, spec: String, profiles: [Profile],
                                      toolchain: Toolchain) async -> State {
        guard let tool = toolchain.ytdlp else { return .problem("yt-dlp isn’t installed.", .none) }
        let file = browserCookieFile
        try? FileManager.default.removeItem(at: file)
        // An unresolvable address: yt-dlp loads the cookies, saves them, then stops — nothing is sent anywhere.
        let args = ["--cookies-from-browser", spec, "--cookies", file.path,
                    "--simulate", "--no-warnings", "--socket-timeout", "5", "--", "https://localhost.invalid/check"]
        let output = try? await ProcessRunner.run(tool, args)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let log = (output?.stderr ?? "") + (output?.stdoutText ?? "")
        let lower = log.lowercased()

        if lower.contains("extracted"), let text = try? String(contentsOf: file, encoding: .utf8) {
            UserDefaults.standard.set(spec, forKey: browserKey)
            UserDefaults.standard.set(Date(), forKey: exportedKey)
            let sites = CookieSites.sites(inCookieFile: text)
            return sites.isEmpty ? noSignIns(browser, profiles: profiles) : .ready(sites)
        }
        try? FileManager.default.removeItem(at: file)
        if lower.contains("operation not permitted") || lower.contains("permission") || lower.contains("could not find") {
            return .problem("macOS is blocking My Videos from reading \(browser.displayName)’s sign-ins. Turn on My Videos in Full Disk Access, then reopen My Videos.", .fullDiskAccess)
        }
        if lower.contains("find-generic-password") || lower.contains("keychain") || lower.contains("safe storage")
            || lower.contains("decrypt") {
            return .problem("\(browser.displayName)’s sign-ins are locked. Check again and click “Always Allow” when macOS asks for “\(browser.displayName) Safe Storage”.", .retry)
        }
        let lastError = log.split(separator: "\n").last { $0.contains("ERROR") }.map(String.init)?
            .replacingOccurrences(of: "ERROR: ", with: "") ?? "Couldn’t read \(browser.displayName)’s sign-ins."
        return .problem(lastError, .retry)
    }

    /// Quits and reopens My Videos — macOS applies a new Full Disk Access setting only to a fresh launch.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
