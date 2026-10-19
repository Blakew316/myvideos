//
//  Skimming.swift
//  My Videos
//
//  Move the pointer across a video's artwork to flip through it, as in Photos and
//  Final Cut. A dozen small frames are pulled once per file and kept in memory.
//

import SwiftUI
import AVFoundation
import AppKit

@MainActor
final class SkimFrames {
    static let shared = SkimFrames()
    nonisolated static let frameCount = 12

    private let cache = NSCache<NSString, NSArray>()
    private var loading: [String: Task<[NSImage], Never>] = [:]

    private init() { cache.countLimit = 60 }

    func cached(_ url: URL) -> [NSImage]? {
        cache.object(forKey: url.path as NSString) as? [NSImage]
    }

    func frames(for url: URL) async -> [NSImage] {
        if let cached = cached(url) { return cached }
        if let task = loading[url.path] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { await Self.generate(url) }
        loading[url.path] = task
        let frames = await task.value
        loading[url.path] = nil
        if !frames.isEmpty { cache.setObject(frames as NSArray, forKey: url.path as NSString) }
        return frames
    }

    nonisolated private static func generate(_ url: URL) async -> [NSImage] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 1 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        // Nearby keyframes are plenty for skimming and much faster to decode.
        let tolerance = CMTime(seconds: duration / Double(frameCount) / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let times = (0..<frameCount).map { i in
            CMTime(seconds: duration * (Double(i) + 0.5) / Double(frameCount), preferredTimescale: 600)
        }
        var images: [NSImage] = []
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            images.append(NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
        }
        return images
    }
}

/// Artwork that flips through the video under the pointer, with a thin playhead.
struct SkimmableArtwork: View {
    let item: HistoryItem
    var cornerRadius: CGFloat = 12
    @State private var fraction: Double?
    @State private var frames: [NSImage] = []
    @State private var width: CGFloat = 1

    private var file: URL? {
        guard !item.isAudio, !item.isPlaylist else { return nil }
        return item.fileURLs.first { MediaPlayer.canPlay($0) }
    }

    var body: some View {
        Thumbnail(url: item.thumbnailURL, isAudio: item.isAudio, cornerRadius: cornerRadius)
            .overlay {
                if let fraction, !frames.isEmpty {
                    let index = min(Int(fraction * Double(frames.count)), frames.count - 1)
                    Image(nsImage: frames[index])
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    if let fraction, !frames.isEmpty {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .offset(x: max(0, min(geo.size.width - 2, geo.size.width * fraction)))
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
            .onContinuousHover { phase in
                guard let file else { return }
                switch phase {
                case .active(let location):
                    fraction = min(max(location.x / width, 0), 0.999)
                    if frames.isEmpty {
                        if let cached = SkimFrames.shared.cached(file) {
                            frames = cached
                        } else {
                            Task { frames = await SkimFrames.shared.frames(for: file) }
                        }
                    }
                case .ended:
                    fraction = nil
                }
            }
    }
}
