//
//  ComposerFlowCheck.swift
//  My Videos Tests
//
//  Drives the real Download page end to end with the full window on screen.
//  Opt-in: TEST_RUNNER_FLOW_DIR=/folder xcodebuild test -only-testing:"My Videos Tests/ComposerFlow"
//

import AppKit
import SwiftUI
import Testing
@testable import My_Videos

@MainActor
@Suite("ComposerFlow", .enabled(if: ProcessInfo.processInfo.environment["FLOW_DIR"] != nil))
struct ComposerFlow {
    private func spin(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    @Test func pasteLinkPreviewAndDownload() async throws {
        let model = AppModel.shared
        let prefs = model.prefs
        let saved = (prefs.destination, prefs.addToMusic, prefs.quality, prefs.notificationsEnabled)
        defer {
            prefs.destination = saved.0; prefs.addToMusic = saved.1; prefs.quality = saved.2; prefs.notificationsEnabled = saved.3
        }
        prefs.destination = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLOW_DIR"]!)
        prefs.addToMusic = false

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 860),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView())
        window.makeKeyAndOrderFront(nil)
        await model.toolchain.refresh()
        await spin(2)

        for quality in [DownloadQuality.p720, .audio] {
            prefs.quality = quality
            model.urlString = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
            for _ in 0..<40 where model.preview == .loading || model.preview == .empty { await spin(0.5) }
            #expect(model.previewInfo != nil, "preview loaded for \(quality.rawValue)")
            model.clipEnabled = true
            await spin(1)
            model.clipEnabled = false
            model.downloadFromComposer()
            for _ in 0..<120 where model.jobs.contains(where: { !$0.isDone }) { await spin(0.5) }
            let job = try #require(model.jobs.last)
            #expect(job.phase == .finished, "\(quality.rawValue): \(job.statusLine)")
            await spin(2)
        }
        window.orderOut(nil)
    }
}
