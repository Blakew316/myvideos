//
//  SettingsView.swift
//  My Videos
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreImage

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Downloads", systemImage: "arrow.down.circle") { DownloadSettings() }
            Tab("Channels", systemImage: "person.2") { ChannelSettings() }
            Tab("Accounts", systemImage: "person.crop.circle") { AccountSettings() }
            Tab("Devices", systemImage: "laptopcomputer.and.iphone") { DeviceSettings() }
            Tab("Advanced", systemImage: "gearshape.2") { AdvancedSettings() }
        }
        .frame(width: 620)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs
    @State private var copiedBookmarklet = false

    /// A bookmark whose “address” sends the current page to My Videos.
    static let bookmarklet = "javascript:location.href='myvideos://download?url='+encodeURIComponent(location.href)"

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
                Toggle("Show downloads in Spotlight", isOn: $prefs.spotlightEnabled)
            } header: {
                Text("Convenience")
            } footer: {
                Text("You can also send links from the Share menu, Services or Siri.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Download button") {
                    HStack {
                        Button(copiedBookmarklet ? "Copied" : "Copy Button Code") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.bookmarklet, forType: .string)
                            copiedBookmarklet = true
                        }
                    }
                }
            } header: {
                Text("Browser")
            } footer: {
                Text("Adds a one-click Download bookmark to your Favorites bar: add any bookmark to Favorites, then paste the copied code as its address.")
                    .foregroundStyle(.secondary)
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

// MARK: - Channels

private struct ChannelSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs

    private var subscriptionFooter: String {
        var parts: [String] = []
        if prefs.subscriptionsOnlyAtNight {
            parts.append("New uploads download between \(QuietHours.hourLabel(prefs.quietStartHour)) and \(QuietHours.hourLabel(prefs.quietEndHour)) while your Mac is awake. “Check Now” always works.")
        }
        if prefs.cleanupAfterDays > 0 {
            parts.append("Only videos you’ve opened are moved to the Trash — unwatched ones stay.")
        }
        return parts.isEmpty ? "Subscriptions check for new uploads while My Videos is open." : parts.joined(separator: " ")
    }

    var body: some View {
        Form {
            Section {
                Picker("Check for new uploads", selection: $prefs.subscriptionInterval) {
                    Text("Every 30 Minutes").tag(30)
                    Text("Every Hour").tag(60)
                    Text("Every 3 Hours").tag(180)
                    Text("Every 6 Hours").tag(360)
                    Text("Once a Day").tag(1440)
                }
                Toggle("Only download during set hours", isOn: $prefs.subscriptionsOnlyAtNight)
                if prefs.subscriptionsOnlyAtNight {
                    HStack {
                        Picker("From", selection: $prefs.quietStartHour) {
                            ForEach(0..<24, id: \.self) { Text(QuietHours.hourLabel($0)).tag($0) }
                        }
                        Picker("to", selection: $prefs.quietEndHour) {
                            ForEach(0..<24, id: \.self) { Text(QuietHours.hourLabel($0)).tag($0) }
                        }
                    }
                }
                Toggle("Wait when on a phone hotspot or Low Data Mode", isOn: $prefs.avoidMeteredNetworks)
                Picker("After watching, move to Trash", selection: $prefs.cleanupAfterDays) {
                    Text("Never").tag(0)
                    Text("After 1 Day").tag(1)
                    Text("After 1 Week").tag(7)
                    Text("After 30 Days").tag(30)
                }
            } header: {
                Text("New Uploads")
            } footer: {
                Text(subscriptionFooter).foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: - Downloads

private struct DownloadSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs
    /// Shared with the New Download sheet, which remembers the last video quality.
    @AppStorage("lastVideoQuality") private var lastVideoQuality = DownloadQuality.best.rawValue

    private var downloadsAudio: Binding<Bool> {
        Binding {
            prefs.quality == .audio
        } set: { audio in
            if audio {
                if prefs.quality != .audio { lastVideoQuality = prefs.quality.rawValue }
                prefs.quality = .audio
            } else {
                prefs.quality = DownloadQuality(rawValue: lastVideoQuality).flatMap { $0 == .audio ? nil : $0 } ?? .best
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Download as", selection: downloadsAudio) {
                    Text("Video").tag(false)
                    Text("Audio").tag(true)
                }
                .pickerStyle(.segmented)
                if prefs.quality == .audio {
                    Picker("Format", selection: $prefs.audioFormat) {
                        ForEach(AudioFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Quality", selection: $prefs.audioBitrate) {
                        ForEach(AudioBitrate.allCases) { Text($0.displayName).tag($0) }
                    }
                    .disabled(prefs.audioFormat == .wav)
                } else {
                    Picker("Quality", selection: $prefs.quality) {
                        ForEach(DownloadQuality.allCases.filter { $0 != .audio }) { Text($0.displayName).tag($0) }
                    }
                    Picker("Subtitles", selection: $prefs.subtitles) {
                        ForEach(SubtitleMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    if prefs.subtitles != .off {
                        Picker("Subtitle language", selection: $prefs.subtitleLanguage) {
                            ForEach(SubtitleLanguage.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                }
            } header: {
                Text("New Downloads")
            } footer: {
                Text("What a new download starts with. You can change it for any download before it starts.")
                    .foregroundStyle(.secondary)
            }

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

            Section {
                Toggle("Add audio downloads to Apple Music", isOn: $prefs.addToMusic)
                Toggle("Find and add lyrics", isOn: $prefs.fetchLyrics)
                Toggle("Even out volume", isOn: $prefs.normalizeVolume)
            } header: {
                Text("Music")
            } footer: {
                Text("Playlists downloaded as audio become an album, with each song numbered in order.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Accounts

private struct AccountSettings: View {
    @Bindable private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            SignInControls(model: model)
            if model.prefs.cookieSource == .builtIn {
                Section {
                    HStack {
                        Button("Sign In to Another Site…") { openWindow(id: "signin") }
                        Spacer()
                        Button("Sign Out of All Sites", role: .destructive) { confirmSignOut = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Sign out of all sites?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await SignInSession.signOutEverywhere()
                    await model.signIn.check(prefs: model.prefs, toolchain: model.toolchain)
                }
            }
        } message: {
            Text("Private videos won’t download until you sign in again.")
        }
    }
}

// MARK: - Devices

private struct DeviceSettings: View {
    var body: some View {
        Form {
            SyncSettings()
            CompanionSettings()
        }
        .formStyle(.grouped)
    }
}

private struct CompanionSettings: View {
    private var model: AppModel { AppModel.shared }
    private var server: CompanionServer { CompanionServer.shared }
    private var pairing: CompanionPairing { CompanionPairing.shared }
    @State private var confirmReset = false

    private var host: String { CompanionServer.bonjourHost ?? CompanionServer.ipAddress ?? "this Mac" }
    private var port: UInt16 { server.port == 0 ? CompanionServer.preferredPort : server.port }
    private var link: String { "http://\(host):\(port)/?code=\(pairing.code)" }

    var body: some View {
        Group {
            Section {
                Toggle("Use My Videos on iPhone and iPad", isOn: Binding(
                    get: { model.prefs.companionEnabled },
                    set: { model.setCompanionEnabled($0) }))
            } header: {
                Text("iPhone and iPad")
            } footer: {
                Text("Send links, follow downloads and watch them on your iPhone over your home Wi-Fi. Your Mac does the downloading, so keep My Videos open (it can stay in the menu bar).")
                    .foregroundStyle(.secondary)
            }

            if model.prefs.companionEnabled {
                Section {
                    HStack(alignment: .center, spacing: 20) {
                        QRCode(text: link)
                            .frame(width: 148, height: 148)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Scan with your iPhone’s Camera")
                                .font(.headline)
                            Text("Then tap Share › Add to Home Screen, open My Videos and enter this code:")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(pairing.code.prefix(3) + " " + pairing.code.suffix(3))
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .tracking(2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 6)
                    LabeledContent("Or open in Safari") {
                        Text("http://\(host):\(port)")
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                    if let ip = CompanionServer.ipAddress, CompanionServer.bonjourHost != nil {
                        LabeledContent("If that doesn’t load") {
                            Text("http://\(ip):\(port)").textSelection(.enabled).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Connect Your iPhone")
                }

                Section {
                    LabeledContent("Status") {
                        if server.isRunning {
                            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if let error = server.lastError {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    LabeledContent("Last used from iPhone",
                                   value: server.lastSeen?.formatted(.relative(presentation: .named)) ?? "Not yet")
                    HStack {
                        Spacer()
                        Button("Disconnect All Devices…", role: .destructive) { confirmReset = true }
                    }
                } footer: {
                    Text("Only devices that entered the code can use My Videos. Disconnecting creates a new code.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Disconnect all iPhones and iPads?", isPresented: $confirmReset) {
            Button("Disconnect", role: .destructive) { pairing.reset() }
        } message: {
            Text("They’ll need the new code to connect again.")
        }
    }
}

/// A crisp QR code rendered with Core Image.
private struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code for \(text)")
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit()
        }
    }

    static func make(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - Sync

private struct SyncSettings: View {
    private var model: AppModel { AppModel.shared }

    var body: some View {
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
            } header: {
                Text("Your Other Macs")
            } footer: {
                Text("Keeps your library, watched progress, collections, channels and download settings the same on every Mac using your iCloud account. Files stay on the Mac that downloaded them.")
                    .foregroundStyle(.secondary)
            }
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
        Group {
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
            ComponentSettings()

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
                Text("Reports stay on this Mac. Save Report creates a file, with the activity log, that you can choose to share.")
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
