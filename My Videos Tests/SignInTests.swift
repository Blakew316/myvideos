//
//  SignInTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("Sign-in")
struct SignInTests {
    private let sample = """
        # Netscape HTTP Cookie File
        .youtube.com\tTRUE\t/\tTRUE\t1893456000\tLOGIN_INFO\tabc
        #HttpOnly_.google.com\tTRUE\t/\tTRUE\t1893456000\tSID\tdef
        .vimeo.com\tTRUE\t/\tTRUE\t1893456000\tvuid\tghi
        .example.com\tTRUE\t/\tFALSE\t0\ttheme\tdark
        """

    @Test func findsSignedInSites() {
        #expect(CookieSites.sites(inCookieFile: sample) == ["google.com", "vimeo.com", "youtube.com"])
        #expect(CookieSites.isNetscapeFile(sample))
        #expect(!CookieSites.isNetscapeFile("{\"cookies\": []}"))
    }

    @MainActor @Test func checksCookieFiles() throws {
        let dir = FileManager.default.temporaryDirectory
        let good = dir.appendingPathComponent("good-cookies.txt")
        let empty = dir.appendingPathComponent("no-signins.txt")
        let json = dir.appendingPathComponent("cookies.json")
        try sample.write(to: good, atomically: true, encoding: .utf8)
        try "# Netscape HTTP Cookie File\n.example.com\tTRUE\t/\tFALSE\t0\ttheme\tdark\n".write(to: empty, atomically: true, encoding: .utf8)
        try "[{\"name\":\"SID\"}]".write(to: json, atomically: true, encoding: .utf8)
        defer { [good, empty, json].forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(SignInStatus.checkFile(good.path) == .ready(["google.com", "vimeo.com", "youtube.com"]))
        if case .problem(_, let fix) = SignInStatus.checkFile(empty.path) { #expect(fix == .chooseFile) } else { Issue.record("expected problem") }
        if case .problem(let message, _) = SignInStatus.checkFile(json.path) { #expect(message.contains("Netscape")) } else { Issue.record("expected problem") }
        if case .problem(_, let fix) = SignInStatus.checkFile("") { #expect(fix == .chooseFile) } else { Issue.record("expected problem") }
        if case .problem(_, let fix) = SignInStatus.checkFile("/nope/missing.txt") { #expect(fix == .chooseFile) } else { Issue.record("expected problem") }
    }

    @Test func siteListReadsNaturally() {
        #expect(SignInControls.list(["youtube.com"]) == "youtube.com")
        #expect(SignInControls.list(["a.com", "b.com", "c.com", "d.com", "e.com"]) == "a.com, b.com, c.com and 2 more")
    }
}
