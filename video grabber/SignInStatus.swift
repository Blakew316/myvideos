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
        case none, signIn, chooseFile, fullDiskAccess, retry
    }

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
            if !readBrowser, let cached = Self.cachedBrowserSites(for: prefs.cookieBrowser) {
                state = cached.isEmpty
                    ? .problem("No sign-ins found in \(prefs.cookieBrowser.displayName). Sign in to the site there first.", .retry)
                    : .ready(cached)
                return
            }
            state = .checking
            let result = await Self.exportBrowser(prefs.cookieBrowser, toolchain: toolchain)
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

    private static func cachedBrowserSites(for browser: CookieBrowser) -> [String]? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: browserKey) == browser.rawValue,
              let exported = defaults.object(forKey: exportedKey) as? Date,
              Date().timeIntervalSince(exported) < 12 * 3600,
              let text = try? String(contentsOf: browserCookieFile, encoding: .utf8) else { return nil }
        return CookieSites.sites(inCookieFile: text)
    }

    /// The cookies.txt downloads should use for the browser method, re-reading the browser if stale.
    func browserCookiesForDownload(prefs: Preferences, toolchain: Toolchain) async -> URL? {
        if Self.cachedBrowserSites(for: prefs.cookieBrowser) == nil {
            state = .checking
            state = await Self.exportBrowser(prefs.cookieBrowser, toolchain: toolchain)
        }
        return FileManager.default.fileExists(atPath: Self.browserCookieFile.path) ? Self.browserCookieFile : nil
    }

    /// Asks yt-dlp to read the browser's cookies (offline) and save them as a private cookies.txt.
    private static func exportBrowser(_ browser: CookieBrowser, toolchain: Toolchain) async -> State {
        guard let tool = toolchain.ytdlp else { return .problem("yt-dlp isn’t installed.", .none) }
        let file = browserCookieFile
        try? FileManager.default.removeItem(at: file)
        // An unresolvable address: yt-dlp loads the cookies, saves them, then stops — nothing is sent anywhere.
        let args = ["--cookies-from-browser", browser.rawValue, "--cookies", file.path,
                    "--simulate", "--no-warnings", "--socket-timeout", "5", "--", "https://localhost.invalid/check"]
        let output = try? await ProcessRunner.run(tool, args)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let log = ((output?.stderr ?? "") + (output?.stdoutText ?? ""))
        let lower = log.lowercased()

        if lower.contains("extracted"), let text = try? String(contentsOf: file, encoding: .utf8) {
            UserDefaults.standard.set(browser.rawValue, forKey: browserKey)
            UserDefaults.standard.set(Date(), forKey: exportedKey)
            let sites = CookieSites.sites(inCookieFile: text)
            return sites.isEmpty
                ? .problem("No sign-ins found in \(browser.displayName). Sign in to the site there, then check again.", .retry)
                : .ready(sites)
        }
        try? FileManager.default.removeItem(at: file)
        if browser == .safari && (lower.contains("operation not permitted") || lower.contains("permission")) {
            return .problem("macOS needs to allow My Videos to read Safari’s sign-ins: turn on My Videos in Full Disk Access.", .fullDiskAccess)
        }
        if lower.contains("keychain") || lower.contains("safe storage") || lower.contains("decrypt") {
            return .problem("\(browser.displayName)’s sign-ins are locked. Check again and choose “Always Allow” when macOS asks.", .retry)
        }
        if lower.contains("could not find") || lower.contains("no such file") || lower.contains("not installed") {
            return .problem("\(browser.displayName) doesn’t seem to be installed or set up on this Mac.", .none)
        }
        let lastError = log.split(separator: "\n").last { $0.contains("ERROR") }.map(String.init)?
            .replacingOccurrences(of: "ERROR: ", with: "") ?? "Couldn’t read \(browser.displayName)’s sign-ins."
        return .problem(lastError, .retry)
    }

    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
