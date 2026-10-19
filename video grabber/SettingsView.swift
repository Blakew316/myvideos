//
//  SettingsView.swift
//  My Videos
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Downloads", systemImage: "arrow.down.circle") { DownloadSettings() }
            Tab("Accounts", systemImage: "person.crop.circle") { AccountSettings() }
            Tab("Sync", systemImage: "icloud") { SyncSettings() }
            Tab("Components", systemImage: "shippingbox") { ComponentSettings() }
            Tab("Advanced", systemImage: "wrench.and.screwdriver") { AdvancedSettings() }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs

    var body: some View {
        Form {
            Section {
                LabeledContent("Save downloads to") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: prefs.destination.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(FileManager.default.displayName(atPath: prefs.destination.path))
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Picker("Organize into folders", selection: $prefs.organize) {
                    ForEach(OrganizeMode.allCases) { Text($0.displayName).tag($0) }
                }
            } header: {
                Text("Saving")
            } footer: {
                Text(organizeExample).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify me when downloads finish", isOn: $prefs.notificationsEnabled)
                Toggle("Offer to download links I copy", isOn: $prefs.clipboardDetection)
                Toggle("Show My Videos in the menu bar", isOn: $prefs.showMenuBarExtra)
            } header: {
                Text("Convenience")
            } footer: {
                Text("You can also select a link in any app and choose Services → Download with My Videos, use the Share menu, or ask Siri to “Download a video with My Videos.”")
                    .foregroundStyle(.secondary)
            }

            Section("Subscriptions") {
                Picker("Check for new uploads", selection: $prefs.subscriptionInterval) {
                    Text("Every 30 Minutes").tag(30)
                    Text("Every Hour").tag(60)
                    Text("Every 3 Hours").tag(180)
                    Text("Every 6 Hours").tag(360)
                    Text("Once a Day").tag(1440)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var organizeExample: String {
        let base = FileManager.default.displayName(atPath: prefs.destination.path)
        switch prefs.organize {
        case .none: return "Everything is saved directly in \(base)."
        case .byType: return "For example: \(base) › Music › Song.m4a"
        case .byChannel: return "For example: \(base) › Channel Name › Video.mp4"
        case .byTypeAndChannel: return "For example: \(base) › Videos › Channel Name › Video.mp4"
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = prefs.destination
        if panel.runModal() == .OK, let url = panel.url { prefs.destination = url }
    }
}

// MARK: - Downloads

private struct DownloadSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs

    var body: some View {
        Form {
            Section {
                Picker("Download at the same time", selection: $prefs.maxConcurrent) {
                    Text("1 at a Time").tag(1)
                    Text("2 at a Time").tag(2)
                    Text("3 at a Time").tag(3)
                }
                Picker("Speed limit", selection: $prefs.speedLimit) {
                    ForEach(SpeedLimit.allCases) { Text($0.displayName).tag($0) }
                }
            } header: {
                Text("Queue")
            } footer: {
                Text("A speed limit keeps downloads from slowing down everything else on your network.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Embed cover art, details and chapters", isOn: $prefs.embedArtwork)
                Picker("Sponsored segments", selection: $prefs.sponsorBlock) {
                    ForEach(SponsorBlockMode.allCases) { Text($0.displayName).tag($0) }
                }
            } header: {
                Text("Videos")
            } footer: {
                Text("Sponsored segments use the community-made SponsorBlock database and apply to YouTube videos.")
                    .foregroundStyle(.secondary)
            }

            Section("Music") {
                Toggle("Add audio downloads to Apple Music", isOn: $prefs.addToMusic)
                Toggle("Find and add lyrics", isOn: $prefs.fetchLyrics)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Accounts

private struct AccountSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs
    @Environment(\.openWindow) private var openWindow
    @State private var signedInSites: [String] = []
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section {
                Picker("Sign in using", selection: $prefs.cookieSource) {
                    ForEach(CookieSource.allCases) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text("Public videos never need a sign-in. Use one for private, members-only or age-restricted videos.")
                    .foregroundStyle(.secondary)
            }

            switch prefs.cookieSource {
            case .none:
                EmptyView()
            case .builtIn:
                Section {
                    if signedInSites.isEmpty {
                        LabeledContent("Signed in to", value: "No sites yet")
                    } else {
                        LabeledContent("Signed in to") {
                            Text(signedInSites.joined(separator: ", "))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Sign In to a Site…") { openWindow(id: "signin") }
                        Spacer()
                        Button("Sign Out of All Sites", role: .destructive) { confirmSignOut = true }
                            .disabled(signedInSites.isEmpty)
                    }
                } header: {
                    Text("My Videos Sign-In")
                } footer: {
                    Text("Sign in once in My Videos’ own browser window. Your sign-ins stay private on this Mac and are only shared with yt-dlp while downloading.")
                        .foregroundStyle(.secondary)
                }
            case .browser:
                Section {
                    Picker("Browser", selection: $prefs.cookieBrowser) {
                        ForEach(CookieBrowser.allCases) { Text($0.displayName).tag($0) }
                    }
                } footer: {
                    Text("Uses the sign-ins from a browser you already use. macOS may ask for permission, and Safari often blocks this — if it fails, use My Videos Sign-In instead.")
                        .foregroundStyle(.secondary)
                }
            case .file:
                Section {
                    LabeledContent("Cookies file") {
                        HStack {
                            Text(prefs.cookieFilePath.isEmpty ? "None" : (prefs.cookieFilePath as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseCookieFile)
                        }
                    }
                } footer: {
                    Text("A Netscape-format cookies.txt exported from a browser where you’re signed in.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: prefs.cookieSource) { await reloadSites() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await reloadSites() }
        }
        .confirmationDialog("Sign out of all sites?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await SignInSession.signOutEverywhere()
                    await reloadSites()
                }
            }
        } message: {
            Text("Private videos won’t download until you sign in again.")
        }
    }

    private func reloadSites() async {
        signedInSites = await SignInSession.signedInSites()
    }

    private func chooseCookieFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.text, .plainText, .item]
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { prefs.cookieFilePath = url.path }
    }
}

// MARK: - Sync

private struct SyncSettings: View {
    private var model: AppModel { AppModel.shared }

    var body: some View {
        Form {
            Section {
                Toggle("Sync with iCloud Drive", isOn: Binding(
                    get: { model.prefs.iCloudSync },
                    set: { model.setSyncEnabled($0) }))
                    .disabled(SyncService.iCloudDrive == nil)
                LabeledContent("Status") {
                    statusView
                }
                if model.prefs.iCloudSync {
                    HStack {
                        Button("Sync Now") { Task { await model.sync.sync(model: model) } }
                            .disabled(model.sync.status == .syncing)
                        Spacer()
                        if let folder = SyncService.folder {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            }
                        }
                    }
                }
            } footer: {
                Text("Keeps your download history, subscriptions and download settings the same on every Mac signed in to your iCloud account. Downloaded files themselves stay on the Mac that downloaded them. Each new upload from a subscription downloads once, on whichever Mac checks first.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.sync.status {
        case .off:
            Text("Off").foregroundStyle(.secondary)
        case .unavailable:
            Label("iCloud Drive is off", systemImage: "icloud.slash")
                .foregroundStyle(.orange)
                .help("Turn on iCloud Drive in System Settings → Apple Account → iCloud.")
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…").foregroundStyle(.secondary)
            }
        case .synced(let date):
            Label("Synced \(date.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.icloud")
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }
}

// MARK: - Components

private struct ComponentSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs
    private var toolchain: Toolchain { AppModel.shared.toolchain }

    var body: some View {
        Form {
            Section {
                LabeledContent("yt-dlp") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(toolchain.ytdlpVersion ?? (toolchain.ytdlp == nil ? "Not installed" : "Unknown version"))
                            .monospacedDigit()
                        if toolchain.updateAvailable, let latest = toolchain.latestYtdlpVersion {
                            Text("Version \(latest) available")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        } else if toolchain.latestYtdlpVersion != nil {
                            Text("Up to date")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("ffmpeg", value: toolchain.ffmpegVersion ?? (toolchain.ffmpeg == nil ? "Not installed" : "Installed"))
                LabeledContent("Browser impersonation") {
                    Label(toolchain.impersonationAvailable ? "Available" : "Unavailable",
                          systemImage: toolchain.impersonationAvailable ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(toolchain.impersonationAvailable ? .green : .secondary)
                }
                .help("Lets downloads get past sites that block automated tools.")

                HStack {
                    if toolchain.operation != nil || toolchain.isCheckingForUpdates {
                        ProgressView().controlSize(.small)
                        Text(toolchain.operation == .installing ? "Installing…"
                             : toolchain.operation == .updating ? "Updating…" : "Checking…")
                            .foregroundStyle(.secondary)
                    } else if let error = toolchain.operationError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !toolchain.isReady && toolchain.brew != nil {
                        Button("Install Missing") { Task { await toolchain.installMissing(log: AppModel.shared.log) } }
                            .disabled(toolchain.operation != nil)
                    } else if toolchain.updateAvailable {
                        Button("Update yt-dlp") { Task { await toolchain.updateYtdlp(log: AppModel.shared.log) } }
                            .disabled(toolchain.operation != nil)
                    } else {
                        Button("Check for Updates") {
                            Task {
                                await toolchain.refresh()
                                await toolchain.checkForUpdates()
                            }
                        }
                        .disabled(toolchain.operation != nil || toolchain.isCheckingForUpdates)
                    }
                }
            } header: {
                Text("Download Tools")
            }

            Section {
                Toggle("Check for yt-dlp updates weekly", isOn: $prefs.autoCheckUpdates)
                if let last = Toolchain.lastUpdateCheck {
                    LabeledContent("Last checked", value: last.formatted(.relative(presentation: .named)))
                }
            } footer: {
                Text("Video sites change often. Keeping yt-dlp current is the best way to keep downloads working.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedSettings: View {
    private var model: AppModel { AppModel.shared }
    private var diagnostics: Diagnostics { Diagnostics.shared }
    private var updater: AppUpdater { AppUpdater.shared }
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("App Updates") {
                LabeledContent("Version", value: updater.currentVersion)
                if updater.isConfigured {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 }))
                    HStack {
                        Spacer()
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                } else {
                    Text("Automatic updates are available in signed releases.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Saved reports", value: diagnostics.reports.isEmpty ? "None" : "\(diagnostics.reports.count)")
                HStack {
                    Button("Save Report…") {
                        diagnostics.exportReport(activityLog: model.activityLog, toolchain: model.toolchain)
                        diagnostics.markSeen()
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(Diagnostics.folder)
                    }
                    Spacer()
                    Button("Delete Reports", role: .destructive) { confirmDelete = true }
                        .disabled(diagnostics.reports.isEmpty)
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("If My Videos crashes or hangs, macOS records a report on this Mac. Nothing is sent anywhere — “Save Report…” creates a file you can choose to share, along with the activity log.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { diagnostics.reload() }
        .confirmationDialog("Delete all saved reports?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { diagnostics.deleteAll() }
        }
    }
}
