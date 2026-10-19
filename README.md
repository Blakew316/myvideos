# My Videos

A Mac app for saving videos and music from across the web, built on [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://ffmpeg.org).

**[Download for Mac](https://github.com/Blakew316/myvideos/releases/latest)** · [Website](https://blakew316.github.io/myvideos/)

## Features

- **Download** from YouTube, Vimeo and thousands of other sites: videos, songs or whole playlists, with a preview before you start.
- **Subscriptions:** follow a channel or playlist and new uploads download automatically.
- **Apple Music:** songs are added with clean titles, artist, cover art and lyrics.
- **Clips, subtitles, chapters and SponsorBlock**, plus a built-in player with Picture in Picture.
- **Convert** any file to AAC, MP3, WAV, H.264, a smaller 720p video or a GIF.
- **Queue:** parallel downloads, pause and resume, reorder, and a speed limit.
- **Everywhere:** menu bar, Share menu, Services, Shortcuts and Siri, plus iCloud Drive sync.

## Building

1. Install the tools: `brew install yt-dlp ffmpeg`. The app also offers to do this on first launch.
2. Open `video grabber.xcodeproj`, choose the **My Videos** scheme, set your signing team on all three targets, and run.
3. Tests: ⌘U, or `xcodebuild test -scheme "My Videos" -destination 'platform=macOS'`.

The app is intentionally not sandboxed, because it runs yt-dlp and ffmpeg.

## Releasing

See the header of [`scripts/release.sh`](scripts/release.sh) for one-time setup (Developer ID, notarization, Sparkle key). Then bump the version and run `scripts/release.sh`. It notarizes the app, publishes a GitHub Release, and updates `docs/appcast.xml` so installed copies update automatically.

## Note

Only download content you have the right to save.
