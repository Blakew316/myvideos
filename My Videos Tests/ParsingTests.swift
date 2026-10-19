//
//  ParsingTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("Parsing and formatting")
struct ParsingTests {
    @Test func timecodes() {
        #expect(Timecode.string(75) == "1:15")
        #expect(Timecode.string(3725) == "1:02:05")
        #expect(Timecode.parse("1:15") == 75)
        #expect(Timecode.parse("1:02:05") == 3725)
        #expect(Timecode.parse("12.5") == 12.5)
        #expect(Timecode.parse("abc") == nil)
        #expect(Timecode.parse("1:2:3:4") == nil)
    }

    @Test func byteSizes() {
        #expect(ByteSize.parse("302.04KiB").map { Int($0) } == 309288)
        #expect(ByteSize.parse("48.00MiB") == 50_331_648.0)
        #expect(ByteSize.parse("1.5GB") == 1_500_000_000)
        #expect(ByteSize.parse("nothing") == nil)
    }

    @Test func versionComparison() {
        #expect(Toolchain.isVersion("2026.09.01", newerThan: "2026.08.19"))
        #expect(Toolchain.isVersion("2026.08.19.1", newerThan: "2026.08.19"))
        #expect(!Toolchain.isVersion("2026.08.19", newerThan: "2026.08.19"))
        #expect(!Toolchain.isVersion("2025.12.31", newerThan: "2026.01.01"))
    }

    @Test func videoMetadata() throws {
        let json = """
        {"_type":"video","id":"jNQXAC9IVRw","title":"Me at the zoo","uploader":"jawed","duration":19,
         "thumbnail":"https://i.ytimg.com/vi/jNQXAC9IVRw/hqdefault.jpg","extractor_key":"Youtube",
         "channel_url":"https://www.youtube.com/channel/UC4QobU6STFB0P71PMvOGN5A","is_live":false}
        """
        let info = try #require(MediaInfo.parse(Data(json.utf8)))
        #expect(info.title == "Me at the zoo")
        #expect(info.uploader == "jawed")
        #expect(info.duration == 19)
        #expect(!info.isPlaylist)
        #expect(info.channelURL?.contains("UC4Q") == true)
        #expect(info.thumbnailURL != nil)
    }

    @Test func playlistMetadataUsesFirstEntryArtwork() throws {
        let json = """
        {"_type":"playlist","id":"PL1","title":"Road Trip","playlist_count":3,
         "entries":[{"id":"a","title":"One","thumbnails":[{"url":"https://img/a-small.jpg"},{"url":"https://img/a-big.jpg"}]},
                    {"id":"b","title":"Two"},{"id":"c","title":"Three"}]}
        """
        let info = try #require(MediaInfo.parse(Data(json.utf8)))
        #expect(info.isPlaylist)
        #expect(info.playlistCount == 3)
        #expect(info.thumbnailURL?.absoluteString == "https://img/a-big.jpg")
    }

    private func info(title: String, uploader: String? = nil, track: String? = nil,
                      artist: String? = nil, album: String? = nil) -> MediaInfo {
        MediaInfo(id: "x", title: title, uploader: uploader, duration: nil, thumbnailURL: nil, webpageURL: nil,
                  site: nil, isPlaylist: false, playlistCount: nil, track: track, artist: artist, album: album,
                  isLive: false, channelURL: nil)
    }

    @Test func songDetailsFromVideoTitle() {
        let tags = info(title: "Daft Punk - Get Lucky (Official Video) [4K]", uploader: "DaftPunkVEVO").suggestedTags
        #expect(tags.title == "Get Lucky")
        #expect(tags.artist == "Daft Punk")
    }

    @Test func songDetailsFromTopicChannel() {
        let tags = info(title: "Some Song", uploader: "Artist - Topic").suggestedTags
        #expect(tags == MusicTags(title: "Some Song", artist: "Artist", album: ""))
    }

    @Test func songDetailsPreferRealMusicMetadata() {
        let tags = info(title: "whatever", track: "Real Track", artist: "Real Artist, Guest", album: "LP").suggestedTags
        #expect(tags == MusicTags(title: "Real Track", artist: "Real Artist", album: "LP"))
    }

    @Test func featuredArtistsUseAppleMusicStyle() {
        let tags = info(title: "Daft Punk - Get Lucky (Official Audio) ft. Pharrell Williams, Nile Rodgers").suggestedTags
        #expect(tags.artist == "Daft Punk")
        #expect(tags.title == "Get Lucky (feat. Pharrell Williams, Nile Rodgers)")
        #expect(MediaInfo.withoutFeaturing(tags.title) == "Get Lucky")
        #expect(MediaInfo.withoutFeaturing("Song [feat. X]") == "Song")
        #expect(MediaInfo.formatFeaturing("Song (feat. X)") == "Song (feat. X)")
        #expect(MediaInfo.formatFeaturing("Aftermath") == "Aftermath")
    }

    @Test func titleCleanupKeepsMeaningfulParentheses() {
        #expect(MediaInfo.cleanTitle("Song (Official Music Video)") == "Song")
        #expect(MediaInfo.cleanTitle("Song (Lyrics)") == "Song")
        #expect(MediaInfo.cleanTitle("Song (feat. Someone)") == "Song (feat. Someone)")
    }

    @Test func ffmpegProgress() {
        #expect(ConvertJob.progressSeconds(from: "out_time_us=3000000") == 3)
        #expect(ConvertJob.progressSeconds(from: "out_time_ms=1500000") == 1.5)
        #expect(ConvertJob.progressSeconds(from: "progress=end") == nil)
    }

    @Test func convertOutputNamesNeverOverwrite() {
        let input = URL(fileURLWithPath: "/tmp/Clip.mp4")
        var existing: Set<String> = ["/tmp/Clip (Smaller).mp4"]
        // Same extension as the input → never the input itself.
        var out = ConvertPreset.outputURL(for: input, preset: .smaller) { existing.contains($0.path) }
        #expect(out.path == "/tmp/Clip (Smaller) 2.mp4")
        existing = []
        out = ConvertPreset.outputURL(for: input, preset: .mp3) { existing.contains($0.path) }
        #expect(out.path == "/tmp/Clip.mp3")
    }

    @Test func gifPresetDropsAudio() {
        let args = ConvertPreset.gif.arguments(input: URL(fileURLWithPath: "/a.mov"), output: URL(fileURLWithPath: "/a.gif"))
        #expect(args.contains("-an"))
        #expect(args.last == "/a.gif")
        #expect(args.contains("-progress"))
    }
}
