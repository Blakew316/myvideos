//
//  video_grabberApp.swift
//  My Videos
//

import SwiftUI
import AppKit

@main
struct MyVideosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var prefs = AppModel.shared.prefs

    var body: some Scene {
        Window("My Videos", id: "main") {
            ContentView()
        }
        .defaultSize(width: 980, height: 820)
        .windowToolbarStyle(.unified)
        .commands { AppCommands() }

        WindowGroup("Player", for: URL.self) { $url in
            if let url {
                PlayerView(url: url)
            }
        }
        .defaultSize(width: 960, height: 600)
        .windowToolbarStyle(.unified(showsTitle: true))

        Window("Sign In", id: "signin") {
            SignInView()
        }
        .defaultSize(width: 1000, height: 760)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $prefs.showMenuBarExtra) {
            MenuBarView()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIcon: View {
    private var model = AppModel.shared

    var body: some View {
        Image(systemName: model.isBusy ? "arrow.down.circle.fill" : "play.square")
            .accessibilityLabel("My Videos")
    }
}

private struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    private var model: AppModel { AppModel.shared }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if AppUpdater.shared.isConfigured {
                Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                    .disabled(!AppUpdater.shared.canCheckForUpdates)
            }
            Button("Check for yt-dlp Updates…") {
                Task {
                    await model.toolchain.refresh()
                    await model.toolchain.checkForUpdates()
                    if !model.toolchain.updateAvailable, model.toolchain.latestYtdlpVersion != nil {
                        model.alert = .init(title: "yt-dlp Is Up to Date",
                                            message: "You have the latest version (\(model.toolchain.ytdlpVersion ?? "")).")
                    }
                }
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Download") {
                show(.home)
                model.focusRequest += 1
            }
            .keyboardShortcut("n")
            Button("Paste and Download") {
                show(.home)
                if model.pasteFromClipboard() { model.downloadFromComposer() }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Add Subscription…") {
                show(.subscriptions)
                model.subscribeRequest = .init(link: "")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Convert Files…") { show(.convert) }
            Divider()
            Button("Sign In to a Site…") { openWindow(id: "signin") }
        }
        CommandGroup(before: .sidebar) {
            Button("Home") { show(.library(.all)) }.keyboardShortcut("1")
            Button("Videos") { show(.library(.videos)) }.keyboardShortcut("2")
            Button("Music") { show(.library(.music)) }.keyboardShortcut("3")
            Button("Channels") { show(.subscriptions) }.keyboardShortcut("4")
            Button("Convert") { show(.convert) }.keyboardShortcut("5")
            Divider()
            Button(model.showDownloads ? "Hide Downloads" : "Show Downloads") {
                show(model.selection ?? .home)
                model.showDownloads.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            Button(model.showActivity ? "Hide Activity" : "Show Activity") { model.showActivity.toggle() }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Divider()
        }
    }

    private func show(_ page: SidebarItem) {
        model.selection = page
        openWindow(id: "main")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.bootstrap()
        _ = AppUpdater.shared
    }

    /// Stay running in the menu bar (or while downloading); otherwise quit with the window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(AppModel.shared.prefs.showMenuBarExtra || AppModel.shared.isBusy)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Downloads Are Still in Progress"
        alert.informativeText = "If you quit now, \(model.pendingCount == 1 ? "the download" : "\(model.pendingCount) downloads") will stop."
        alert.addButton(withTitle: "Keep Downloading")
        alert.addButton(withTitle: "Quit")
        alert.buttons[1].hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            // Stop yt-dlp/ffmpeg too, or they'd keep downloading in the background.
            model.cancelAll()
            return .terminateNow
        }
        return .terminateCancel
    }

    /// myvideos://download?url=… from the Share extension or Shortcuts; video and audio
    /// files dropped on the Dock icon (or opened with My Videos) go to Convert.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where !url.isFileURL { AppModel.shared.handleIncoming(url) }
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { AppModel.shared.stage(files) }
        NSApp.activate()
    }
}
