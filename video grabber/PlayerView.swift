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
