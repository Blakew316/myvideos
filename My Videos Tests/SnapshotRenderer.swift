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

    @Test func screens() {
        let model = AppModel.shared
        render("download", size: CGSize(width: 760, height: 900)) { ComposerView(model: model) }
        render("convert", size: CGSize(width: 760, height: 700)) { ConvertView(model: model) }
        render("subscriptions-empty", size: CGSize(width: 760, height: 500)) { SubscriptionsOverview(model: model) }
        render("queue-empty", size: CGSize(width: 760, height: 500)) { QueueView(model: model) }
        render("onboarding", size: CGSize(width: 580, height: 660)) { OnboardingView(model: model) }
        render("subscribe-sheet", size: CGSize(width: 520, height: 300)) { SubscribeSheet(model: model, link: "") }
        render("settings", size: CGSize(width: 600, height: 640)) { SettingsView() }
        render("menubar", size: CGSize(width: 340, height: 260)) { MenuBarView() }
        render("main-window", size: CGSize(width: 1100, height: 860)) { ContentView() }
    }
}
