//
//  MusicLibrary.swift
//  My Videos
//

import Foundation

/// Adds files to Apple Music through AppleScript.
nonisolated enum MusicLibrary {
    enum ImportError: LocalizedError {
        case permissionDenied
        case unsupportedFormat(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "macOS blocked Automation access to Music. Open System Settings → Privacy & Security → Automation, turn on “Music” for My Videos, then try again."
            case .unsupportedFormat(let ext):
                return "Apple Music can’t import .\(ext) files. Choose AAC or MP3 as the audio format."
            case .failed(let message):
                return message
            }
        }
    }

    static let unsupportedExtensions: Set<String> = ["opus", "ogg", "webm", "mkv", "flac"]

    static func canImport(_ url: URL) -> Bool {
        !unsupportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Adds a file to Music and tags it. The path and tags arrive as argv, so no string
    /// escaping is needed. Each tag is set inside its own try: Music can intermittently
    /// refuse to rewrite one tag without failing the others.
    private static let script = """
        on run argv
            set theFile to POSIX file (item 1 of argv)
            set theTitle to item 2 of argv
            set theArtist to item 3 of argv
            set theAlbum to item 4 of argv
            tell application "Music"
                set newTrack to add theFile
                if newTrack is missing value then error "Apple Music couldn’t import this file." number 1
                delay 0.5
                if theTitle is not "" then
                    try
                        set name of newTrack to theTitle
                    end try
                end if
                if theArtist is not "" then
                    try
                        set artist of newTrack to theArtist
                    end try
                end if
                if theAlbum is not "" then
                    try
                        set album of newTrack to theAlbum
                    end try
                end if
            end tell
        end run
        """

    /// Runs through /usr/bin/osascript: NSAppleScript must only be used on the main thread
    /// (where it would freeze the UI), while a child process can be awaited without blocking.
    /// Automation permission is still attributed to My Videos, the responsible process.
    static func add(_ file: URL, tags: MusicTags) async throws {
        guard canImport(file) else { throw ImportError.unsupportedFormat(file.pathExtension) }
        let output = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"),
                                                 ["-e", script, file.path,
                                                  tags.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  tags.artist.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  tags.album.trimmingCharacters(in: .whitespacesAndNewlines)])
        guard output.status != 0 else { return }
        // -1743 == errAEEventNotPermitted: Automation access to Music hasn't been granted.
        if output.stderr.contains("-1743") || output.stderr.localizedCaseInsensitiveContains("not authorized") {
            throw ImportError.permissionDenied
        }
        // osascript errors look like "0:123: execution error: <message> (<number>)".
        var message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = message.range(of: "execution error: ") {
            message = String(message[range.upperBound...])
        }
        throw ImportError.failed(message.isEmpty ? "Apple Music refused to import the file." : message)
    }
}
