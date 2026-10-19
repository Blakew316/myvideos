//
//  SnapshotRenderer.swift
//  My Videos Tests
//
//  Renders key screens to PNGs for design review. Runs only when a folder is given:
//  TEST_RUNNER_SNAPSHOT_DIR=/path xcodebuild test -scheme "My Videos" -only-testing:"My Videos Tests/Snapshots"
//

import AppKit
import SwiftUI
import Testing
@testable import My_Videos

@MainActor
@Suite("Snapshots", .enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil))
struct Snapshots {
    private let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? "/tmp")

    private func render<V: View>(_ name: String, size: CGSize, @ViewBuilder _ view: () -> V) {
        for dark in [false, true] {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: view().frame(width: size.width, height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            window.orderBack(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            // The cached bitmap is translucent; flatten it onto the window background so it
            // looks the way it does on screen.
            let scale = CGFloat(rep.pixelsWide) / size.width
            guard let flat = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: flat) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            window.appearance?.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)).fill()
            }
            rep.draw(in: NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            let url = folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
            try? flat.representation(using: .png, properties: [:])?.write(to: url)
            window.orderOut(nil)
        }
    }

    @Test func screens() async {
        let model = AppModel.shared
        let art = (1...8).map { URL(fileURLWithPath: "/private/tmp/claude-501/-Users-justin-video-grabber-video-grabber-xcodeproj/c8172389-965f-4fab-8247-94d6ef823621/scratchpad/art/a\($0).jpg") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        func sample(_ i: Int, _ title: String, _ channel: String, audio: Bool = false, daysAgo: Double = 0) -> HistoryItem {
            HistoryItem(title: title, uploader: channel, sourceURL: "https://example.com/\(i)",
                        thumbnailURL: art.isEmpty ? nil : art[i % art.count], filePaths: ["/tmp"],
                        date: Date().addingTimeInterval(-daysAgo * 86400), isAudio: audio, isPlaylist: false,
                        duration: Double(60 + i * 37), byteCount: 1_000_000)
        }
        let items = [sample(0, "Atom Animation — Free Public Domain Footage", "Public Domain Archive"),
                     sample(1, "Me at the zoo", "jawed"),
                     sample(2, "Get Lucky (feat. Pharrell Williams)", "Daft Punk", audio: true),
                     sample(3, "8mm Countdown Leader", "Archive Films", daysAgo: 3),
                     sample(4, "City at Night, Time-lapse", "Skyline Studio", daysAgo: 4),
                     sample(5, "Morning Jazz", "Cafe Sessions", audio: true, daysAgo: 5)]
        let downloading = DownloadJob(url: "https://example.com/d", options: DownloadOptions(destinationPath: "/tmp"),
                                      info: MediaInfo(id: "d", title: "Big Buck Bunny (4K)", uploader: "Blender", duration: 600,
                                                      thumbnailURL: art.last, webpageURL: nil, site: nil, isPlaylist: false,
                                                      playlistCount: nil, track: nil, artist: nil, album: nil, isLive: false, channelURL: nil),
                                      tags: MusicTags())
        let columns = [GridItem(.adaptive(minimum: 208, maximum: 290), spacing: 22, alignment: .top)]
        func header(_ title: String, _ count: Int) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.title2.weight(.bold))
                Text("\(count)").font(.callout.weight(.medium)).foregroundStyle(.tertiary)
            }
        }
        render("library", size: CGSize(width: 980, height: 860)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 14) {
                        header("Downloading", 1)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                            PendingCard(job: downloading, model: model)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        header("Today", 3)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                            ForEach(items.prefix(3)) { LibraryCard(item: $0, isSelected: $0.title == "Me at the zoo", play: {}, select: { _ in }) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        header("This Week", 3)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                            ForEach(items.suffix(3)) { LibraryCard(item: $0, isSelected: false, play: {}, select: { _ in }) }
                        }
                    }
                }
                .padding(28)
            }
            .background(WindowBackdrop())
        }
        render("library-top", size: CGSize(width: 980, height: 560)) {
            VStack(alignment: .leading, spacing: 30) {
                HStack { AddLinkField(model: model) }.frame(maxWidth: .infinity)
                FeaturedCard(item: items[1], model: model, play: {})
                QuickActions(model: model)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(WindowBackdrop())
        }
        render("toolbar-controls", size: CGSize(width: 760, height: 70)) {
            HStack(spacing: 20) {
                AddLinkField(model: model)
                DownloadsToolbarButton(model: model).buttonStyle(.bordered)
            }
            .padding(16)
        }
        await model.toolchain.refresh()
        model.urlString = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        for _ in 0..<40 where model.previewInfo == nil { try? await Task.sleep(for: .milliseconds(500)) }
        render("add-card", size: CGSize(width: 480, height: 330)) { AddCard(model: model) }
        render("downloads-popover", size: CGSize(width: 440, height: 200)) { DownloadsPopover(model: model) }
        model.urlString = ""
    }
}
