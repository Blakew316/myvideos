//
//  FeedAndSyncTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("Subscriptions and sync")
struct FeedAndSyncTests {
    @Test(arguments: [
        ("https://www.youtube.com/@jawed", "https://www.youtube.com/@jawed/videos"),
        ("https://www.youtube.com/@jawed/", "https://www.youtube.com/@jawed/videos"),
        ("https://www.youtube.com/@jawed/featured", "https://www.youtube.com/@jawed/videos"),
        ("https://www.youtube.com/channel/UC123", "https://www.youtube.com/channel/UC123/videos"),
        ("https://www.youtube.com/@jawed/shorts", "https://www.youtube.com/@jawed/shorts"),
        ("https://www.youtube.com/playlist?list=PL1", "https://www.youtube.com/playlist?list=PL1"),
        ("https://vimeo.com/channels/staffpicks", "https://vimeo.com/channels/staffpicks"),
    ])
    func channelLinksPointAtVideos(input: String, expected: String) {
        #expect(FeedParser.normalize(input) == expected)
    }

    @Test func feedLinkDetection() {
        #expect(FeedParser.looksLikeFeed("https://www.youtube.com/@jawed"))
        #expect(FeedParser.looksLikeFeed("https://www.youtube.com/playlist?list=PL1"))
        #expect(!FeedParser.looksLikeFeed("https://www.youtube.com/watch?v=abc&list=PL1"))
    }

    @Test func channelHomeRedirectsToVideosTab() throws {
        let json = """
        {"_type":"playlist","id":"UC1","title":"Apple TV","channel":"Apple TV","entries":[
          {"_type":"playlist","id":"UC1","title":"Apple TV - Videos","webpage_url":"https://www.youtube.com/channel/UC1/videos"},
          {"_type":"playlist","id":"UC1","title":"Apple TV - Shorts","webpage_url":"https://www.youtube.com/channel/UC1/shorts"}]}
        """
        let feed = try #require(FeedParser.parse(Data(json.utf8)))
        #expect(feed.videosTabURL == "https://www.youtube.com/channel/UC1/videos")
        #expect(feed.entries.isEmpty)
    }

    @Test func channelFeedEntriesAndAvatar() throws {
        let json = """
        {"_type":"playlist","id":"UC4Q","title":"jawed - Videos","channel":"jawed",
         "thumbnails":[{"id":"0","url":"https://banner"},{"id":"avatar_uncropped","url":"https://avatar"}],
         "entries":[{"_type":"url","ie_key":"Youtube","id":"new1","title":"Newest","url":"https://www.youtube.com/watch?v=new1","duration":10},
                    {"_type":"url","ie_key":"Youtube","id":"old1","title":"Older"}]}
        """
        let feed = try #require(FeedParser.parse(Data(json.utf8)))
        #expect(feed.title == "jawed")
        #expect(feed.avatarURL?.absoluteString == "https://avatar")
        #expect(feed.entries.map(\.id) == ["new1", "old1"])
        #expect(feed.entries[1].url == "https://www.youtube.com/watch?v=old1")
    }

    @Test func onlyUnseenUploadsDownloadOldestFirst() {
        let feed = Feed(title: "x", avatarURL: nil, entries: [
            FeedEntry(id: "c", title: "C", url: "https://x/c"),
            FeedEntry(id: "b", title: "B", url: "https://x/b"),
            FeedEntry(id: "a", title: "A", url: "https://x/a"),
        ], videosTabURL: nil)
        #expect(FeedParser.newEntries(in: feed, seen: ["a"]).map(\.id) == ["b", "c"])
        #expect(FeedParser.newEntries(in: feed, seen: ["a", "b", "c"]).isEmpty)
    }

    @Test func subscriptionOptionsUseItsFolderAndFormat() {
        var sub = Subscription(url: "https://www.youtube.com/@x/videos", title: "Channel X")
        sub.isAudio = true
        sub.addToMusic = false
        var base = DownloadOptions(destinationPath: "/tmp")
        base.downloadPlaylist = true
        base.clip = 1...2
        let options = sub.options(from: base)
        #expect(options.quality == .audio)
        #expect(options.subfolder == "Channel X")
        #expect(!options.addToMusic)
        #expect(!options.downloadPlaylist)
        #expect(options.clip == nil)
    }

    // MARK: Sync merge

    private func item(_ title: String, daysAgo: Double, id: UUID = UUID()) -> HistoryItem {
        HistoryItem(id: id, title: title, uploader: nil, sourceURL: "https://x", thumbnailURL: nil, filePaths: [],
                    date: Date().addingTimeInterval(-daysAgo * 86400), isAudio: false, isPlaylist: false,
                    duration: nil, byteCount: nil, deviceName: nil)
    }

    @Test func historyMergeUnionsAndRespectsDeletions() {
        let shared = item("Shared", daysAgo: 3)
        let deleted = item("Deleted elsewhere", daysAgo: 2)
        let local = SyncPayload(history: [item("Local", daysAgo: 1), shared, deleted])
        let remote = SyncPayload(history: [item("Remote", daysAgo: 0), shared], historyTombstones: [deleted.id])
        let merged = SyncMerge.merge(local: local, remote: remote)
        #expect(merged.history.map(\.title) == ["Remote", "Local", "Shared"])
        #expect(merged.historyTombstones.contains(deleted.id))
    }

    @Test func subscriptionMergeKeepsNewestChoicesAndAllSeenUploads() {
        let id = UUID()
        var mine = Subscription(id: id, url: "u", title: "Old Name", createdAt: Date(timeIntervalSince1970: 0))
        mine.seenIDs = ["a", "b"]
        mine.modifiedAt = Date(timeIntervalSince1970: 100)
        var theirs = Subscription(id: id, url: "u", title: "New Name", createdAt: Date(timeIntervalSince1970: 0))
        theirs.seenIDs = ["b", "c"]
        theirs.isEnabled = false
        theirs.modifiedAt = Date(timeIntervalSince1970: 200)
        theirs.settingsModifiedAt = Date(timeIntervalSince1970: 200)
        let merged = SyncMerge.mergeSubscription(mine, theirs)
        #expect(merged.title == "New Name")
        #expect(!merged.isEnabled)
        #expect(Set(merged.seenIDs) == ["a", "b", "c"])
    }

    @Test func userChoiceBeatsANewerRoutineCheck() {
        let id = UUID()
        // Mac A: the user turned the subscription off at t=100.
        var macA = Subscription(id: id, url: "u", title: "X", createdAt: Date(timeIntervalSince1970: 0))
        macA.isEnabled = false
        macA.settingsModifiedAt = Date(timeIntervalSince1970: 100)
        macA.modifiedAt = Date(timeIntervalSince1970: 100)
        // Mac B: an automatic check at t=200 that hasn't seen that change yet.
        var macB = Subscription(id: id, url: "u", title: "X", createdAt: Date(timeIntervalSince1970: 0))
        macB.seenIDs = ["new"]
        macB.lastChecked = Date(timeIntervalSince1970: 200)
        macB.modifiedAt = Date(timeIntervalSince1970: 200)
        let merged = SyncMerge.mergeSubscription(macA, macB)
        #expect(!merged.isEnabled)
        #expect(merged.seenIDs == ["new"])
        #expect(merged.lastChecked == Date(timeIntervalSince1970: 200))
    }

    @Test func removedSubscriptionsStayRemoved() {
        let sub = Subscription(url: "u", title: "Gone")
        let local = SyncPayload(subscriptions: [], subscriptionTombstones: [sub.id])
        let remote = SyncPayload(subscriptions: [sub])
        #expect(SyncMerge.merge(local: local, remote: remote).subscriptions.isEmpty)
    }

    @Test func newerSettingsWin() {
        func settings(_ quality: DownloadQuality, at time: TimeInterval) -> SyncedSettings {
            SyncedSettings(modified: Date(timeIntervalSince1970: time), quality: quality, audioFormat: .m4a,
                           audioBitrate: .best, subtitles: .off, subtitleLanguage: .en, embedArtwork: true,
                           addToMusic: true, fetchLyrics: true, sponsorBlock: .off, organize: .none,
                           speedLimit: .unlimited, maxConcurrent: 1, subscriptionInterval: 60)
        }
        let merged = SyncMerge.merge(local: SyncPayload(settings: settings(.p720, at: 10)),
                                     remote: SyncPayload(settings: settings(.audio, at: 20)))
        #expect(merged.settings?.quality == .audio)
    }

    // MARK: Lyrics

    @Test func lyricsPickClosestLength() {
        let matches = [
            Lyrics.Match(trackName: "Remix", artistName: "A", duration: 630, plainLyrics: "remix words"),
            Lyrics.Match(trackName: "Song", artistName: "A", duration: 249, plainLyrics: "real words"),
            Lyrics.Match(trackName: "Instrumental", artistName: "A", duration: 248, plainLyrics: nil, instrumental: true),
        ]
        #expect(Lyrics.best(of: matches, duration: 248)?.plainLyrics == "real words")
        #expect(Lyrics.best(of: matches, duration: 100) == nil)
    }

    @Test func syncedLyricsFallBackToPlainText() {
        let match = Lyrics.Match(syncedLyrics: "[00:01.00] Hello\n[00:02.50] World")
        #expect(Lyrics.usable(match) == "Hello\nWorld")
    }
}
