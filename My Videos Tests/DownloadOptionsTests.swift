//
//  DownloadOptionsTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("Download arguments")
struct DownloadOptionsTests {
    private let printFile = URL(fileURLWithPath: "/tmp/printed.txt")

    private func arguments(_ options: DownloadOptions, url: String = "https://example.com/v?a=1&b=2") -> [String] {
        options.arguments(url: url, ffmpegDirectory: URL(fileURLWithPath: "/opt/homebrew/bin"),
                          impersonate: true, cookieArguments: [], printFile: printFile)
    }

    private func outputTemplate(_ args: [String]) -> String {
        args[args.firstIndex(of: "-o")! + 1]
    }

    @Test func linkIsLastAfterSeparator() {
        let args = arguments(DownloadOptions(destinationPath: "/tmp/out"))
        #expect(args.suffix(2) == ["--", "https://example.com/v?a=1&b=2"])
    }

    @Test func videoDefaults() {
        let args = arguments(DownloadOptions(destinationPath: "/tmp/out"))
        #expect(args.contains("--no-playlist"))
        #expect(args.contains("--embed-thumbnail"))
        #expect(args.contains("--embed-chapters"))
        #expect(args.contains("--impersonate"))
        #expect(!args.contains("--write-subs"))
        #expect(!args.contains("--limit-rate"))
        #expect(outputTemplate(args) == "/tmp/out/%(title).150B.%(ext)s")
    }

    @Test func opusEmbedsDetailsButNotArtwork() {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        options.quality = .audio
        options.audioFormat = .opus
        let args = arguments(options)
        #expect(args.contains("-x"))
        #expect(args.contains("--embed-metadata"))
        #expect(!args.contains("--embed-thumbnail"))
    }

    @Test func subtitlesUseExactLanguageCodes() {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        options.subtitles = .file
        options.subtitleLanguage = .es
        let args = arguments(options)
        #expect(args.contains("es,es-orig"))
        #expect(args.contains("--convert-subs"))
        #expect(!args.contains("--embed-subs"))
    }

    @Test func clipSkipsSponsorBlock() {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        options.clip = 3...9
        options.sponsorBlock = .remove
        let args = arguments(options)
        #expect(args.contains("*3.00-9.00"))
        #expect(!args.contains("--sponsorblock-remove"))
        #expect(outputTemplate(args).hasSuffix("%(title).150B (Clip).%(ext)s"))
    }

    @Test func sponsorBlockModes() {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        options.sponsorBlock = .mark
        #expect(arguments(options).contains("--sponsorblock-mark"))
        #expect(!arguments(options).contains("--sponsorblock-remove"))
        options.sponsorBlock = .remove
        #expect(arguments(options).contains("sponsor,selfpromo,interaction"))
    }

    @Test func playlistLimitAndFolder() {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        options.downloadPlaylist = true
        options.playlistLimit = 2
        let args = arguments(options)
        #expect(args.contains("--yes-playlist"))
        #expect(args.contains("1:2"))
        #expect(!args.contains("--max-downloads"))
        #expect(outputTemplate(args).contains("%(playlist_title,playlist_id|Playlist)s/%(playlist_index)03d - "))
    }

    @Test(arguments: [
        (OrganizeMode.none, false, "/tmp/out/%(title).150B.%(ext)s"),
        (.byType, true, "/tmp/out/Music/%(title).150B.%(ext)s"),
        (.byType, false, "/tmp/out/Videos/%(title).150B.%(ext)s"),
        (.byChannel, false, "/tmp/out/%(channel,uploader|Other)s/%(title).150B.%(ext)s"),
        (.byTypeAndChannel, true, "/tmp/out/Music/%(channel,uploader|Other)s/%(title).150B.%(ext)s"),
    ])
    func organizeTemplates(mode: OrganizeMode, audio: Bool, expected: String) {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        options.organize = mode
        if audio { options.quality = .audio }
        #expect(outputTemplate(arguments(options)) == expected)
    }

    @Test func subscriptionSubfolderIsSanitized() {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        options.subfolder = "AC/DC 100%"
        #expect(outputTemplate(arguments(options)) == "/tmp/out/AC-DC 100%%/%(title).150B.%(ext)s")
    }

    @Test func speedLimit() {
        var options = DownloadOptions(destinationPath: "/tmp/out")
        options.speedLimit = .five
        let args = arguments(options)
        #expect(args[args.firstIndex(of: "--limit-rate")! + 1] == "5M")
    }
}
