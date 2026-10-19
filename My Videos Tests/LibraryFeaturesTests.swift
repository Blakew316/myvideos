//
//  LibraryFeaturesTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("Watched state, collections and their sync")
struct LibraryFeaturesTests {
    private func item(_ title: String = "Clip", channel: String? = "Channel", audio: Bool = false,
                      minutes: Double = 10, daysAgo: Double = 0) -> HistoryItem {
        HistoryItem(title: title, uploader: channel, sourceURL: "https://example.com/\(title)", thumbnailURL: nil,
                    filePaths: ["/tmp/\(title).mp4"], date: Date().addingTimeInterval(-daysAgo * 86400),
                    isAudio: audio, isPlaylist: false, duration: minutes * 60, byteCount: nil)
    }

    @Test func openedItemsCountAsWatchedUntilMarkedOtherwise() {
        var clip = item()
        #expect(!clip.isWatched)
        clip.lastPlayedAt = Date()
        #expect(clip.isWatched)  // older libraries: anything opened was watched
        clip.watched = false
        #expect(!clip.isWatched)
    }

    @Test func watchProgressIsAFractionOfTheLength() {
        var clip = item(minutes: 10)
        #expect(clip.watchProgress == nil)
        clip.playbackPosition = 150
        #expect(clip.watchProgress == 0.25)
    }

    @Test func smartRulesMatchEveryRuleThatIsSet() {
        let long = item("Long", channel: "Lectures", minutes: 45)
        let short = item("Short", channel: "Lectures", minutes: 3)
        let song = item("Song", channel: "Band", audio: true, minutes: 4)
        var started = item("Started", minutes: 30)
        started.playbackPosition = 60
        let old = item("Old", minutes: 30, daysAgo: 40)

        #expect(SmartRules(minMinutes: 20).matches(long))
        #expect(!SmartRules(minMinutes: 20).matches(short))
        #expect(SmartRules(kind: .audio).matches(song))
        #expect(!SmartRules(kind: .video).matches(song))
        #expect(SmartRules(channel: "lect").matches(short))
        #expect(!SmartRules(channel: "lect").matches(song))
        #expect(SmartRules(watched: .inProgress).matches(started))
        #expect(!SmartRules(watched: .unwatched).matches(started))
        #expect(SmartRules(watched: .unwatched).matches(long))
        #expect(!SmartRules(addedWithinDays: 30).matches(old))
        #expect(!SmartRules(kind: .video, maxMinutes: 10).matches(long))
    }

    @Test func handMadeCollectionsHoldTheirItems() {
        let a = item("A"), b = item("B")
        let collection = LibraryCollection(name: "Favorites", itemIDs: [a.id])
        #expect(collection.includes(a))
        #expect(!collection.includes(b))
    }

    @Test func newerWatchStateFromAnotherMacWins() {
        var mine = item()
        mine.watched = false
        mine.watchModifiedAt = Date().addingTimeInterval(-60)
        var theirs = mine
        theirs.watched = true
        theirs.watchModifiedAt = Date()
        theirs.title = "Renamed elsewhere"

        let merged = SyncMerge.merge(local: SyncPayload(history: [mine]), remote: SyncPayload(history: [theirs]))
        #expect(merged.history.first?.watched == true)
        #expect(merged.history.first?.title == mine.title)  // everything else: this Mac wins
    }

    @Test func collectionsMergeByNewestEditAndStayDeleted() {
        var mine = LibraryCollection(name: "Old Name")
        mine.modifiedAt = Date().addingTimeInterval(-60)
        var theirs = mine
        theirs.name = "New Name"
        theirs.modifiedAt = Date()
        let deleted = LibraryCollection(name: "Gone")

        let merged = SyncMerge.merge(
            local: SyncPayload(collections: [mine, deleted]),
            remote: SyncPayload(collections: [theirs], collectionTombstones: [deleted.id]))
        #expect(merged.collections?.map(\.name) == ["New Name"])
    }

    @Test func payloadsFromOlderVersionsStillDecode() throws {
        let json = #"{"history":[],"historyTombstones":[],"subscriptions":[],"subscriptionTombstones":[]}"#
        let payload = try JSONDecoder().decode(SyncPayload.self, from: Data(json.utf8))
        #expect(payload.collections == nil)
    }
}
