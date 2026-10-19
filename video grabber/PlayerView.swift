//
//  PlayerView.swift
//  My Videos
//

import SwiftUI
import AVKit
import AVFoundation

/// Which downloads can play in the built-in player (AVFoundation can't play WebM/Opus).
enum MediaPlayer {
    static let playableExtensions: Set<String> = ["mp4", "m4v", "mov", "m4a", "mp3", "wav", "aac", "aiff", "caf"]

    static func canPlay(_ url: URL) -> Bool {
        playableExtensions.contains(url.pathExtension.lowercased()) && FileManager.default.fileExists(atPath: url.path)
    }

    static func isAudio(_ url: URL) -> Bool {
        ["m4a", "mp3", "wav", "aac", "aiff", "caf"].contains(url.pathExtension.lowercased())
    }
}

/// A player window: system playback controls, Picture in Picture, and — for songs —
/// the cover art over a soft blurred backdrop.
struct PlayerView: View {
    let url: URL
    @State private var player: AVPlayer
    @State private var artwork: NSImage?
    @State private var title = ""
    @State private var artist = ""
    @State private var savedFrame: URL?
    @State private var frameError = false

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            if MediaPlayer.isAudio(url) {
                audioBackdrop
            } else {
                Color.black.ignoresSafeArea()
            }
            PlayerLayerView(player: player, isAudio: MediaPlayer.isAudio(url))
        }
        .frame(minWidth: 480, minHeight: MediaPlayer.isAudio(url) ? 420 : 270)
        .navigationTitle(title.isEmpty ? url.deletingPathExtension().lastPathComponent : title)
        .navigationSubtitle(artist)
        .toolbar {
            if !MediaPlayer.isAudio(url) {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await saveFrame() }
                    } label: {
                        Label("Save Frame", systemImage: "camera")
                    }
                    .help("Save the current frame as an image (⇧⌘S)")
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                }
            }
        }
        .overlay(alignment: .top) {
            if let savedFrame {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([savedFrame])
                } label: {
                    Label("Saved “\(savedFrame.lastPathComponent)” — Show in Finder", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if frameError {
                Label("Couldn’t save this frame.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 14)
            }
        }
        .animation(.smooth(duration: 0.3), value: savedFrame)
        .task { await loadMetadata() }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }

    private var audioBackdrop: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.7)
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [Brand.indigo.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            VStack(spacing: 18) {
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().scaledToFit()
                    } else {
                        AppGlyph(size: 180)
                    }
                }
                .frame(maxWidth: 260, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                VStack(spacing: 4) {
                    Text(title.isEmpty ? url.deletingPathExtension().lastPathComponent : title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if !artist.isEmpty {
                        Text(artist).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                Spacer().frame(height: 60)
            }
            .padding(.top, 30)
        }
    }

    /// Saves the paused (or current) frame at full resolution as a PNG next to the video.
    private func saveFrame() async {
        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        do {
            let (image, _) = try await generator.image(at: time)
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            let stamp = Timecode.string(time.seconds).replacingOccurrences(of: ":", with: ".")
            var output = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) — \(stamp).png")
            var n = 2
            while FileManager.default.fileExists(atPath: output.path) {
                output = output.deletingLastPathComponent()
                    .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) — \(stamp) \(n).png")
                n += 1
            }
            try data.write(to: output)
            frameError = false
            savedFrame = output
            try? await Task.sleep(for: .seconds(4))
            if savedFrame == output { savedFrame = nil }
        } catch {
            frameError = true
            try? await Task.sleep(for: .seconds(3))
            frameError = false
        }
    }

    private func loadMetadata() async {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return }
        for item in items {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                title = (try? await item.load(.stringValue)) ?? title
            case .commonKeyArtist:
                artist = (try? await item.load(.stringValue)) ?? artist
            case .commonKeyArtwork:
                if let data = try? await item.load(.dataValue) { artwork = NSImage(data: data) }
            default:
                break
            }
        }
    }
}

private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    let isAudio: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = !isAudio
        view.showsFullScreenToggleButton = !isAudio
        view.showsSharingServiceButton = true
        // Let the cover-art backdrop show through for songs.
        if isAudio {
            view.wantsLayer = true
            view.layer?.backgroundColor = .clear
        }
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
