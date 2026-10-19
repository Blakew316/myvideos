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
        await model.toolchain.refresh()
        model.urlString = ""
        try? await Task.sleep(for: .milliseconds(300))
        render("download-empty", size: CGSize(width: 820, height: 760)) { ComposerView(model: model) }
        model.urlString = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        for _ in 0..<40 where model.previewInfo == nil { try? await Task.sleep(for: .milliseconds(500)) }
        render("download-video", size: CGSize(width: 820, height: 900)) { ComposerView(model: model) }
        let quality = model.prefs.quality
        model.prefs.quality = .audio
        render("download-audio", size: CGSize(width: 820, height: 900)) { ComposerView(model: model) }
        render("download-options-audio", size: CGSize(width: 400, height: 560)) { DownloadOptionsPanel(model: model) }
        model.prefs.quality = quality == .audio ? .best : quality
        model.clipEnabled = true
        render("download-options-video", size: CGSize(width: 400, height: 560)) { DownloadOptionsPanel(model: model) }
        model.clipEnabled = false
        model.prefs.quality = quality
        model.urlString = ""
    }
}
