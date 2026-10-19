//
//  ComposerView.swift
//  My Videos
//
//  The Download page: one calm, focused task. Paste a link, see what it is, choose
//  Video or Audio, download. Everything else lives in Options or Settings.
//

import SwiftUI
import AppKit

struct ComposerView: View {
    @Bindable var model: AppModel
    @Bindable private var settings: Preferences
    @FocusState private var urlFocused: Bool
    @State private var showOptions = false
    @Environment(\.openWindow) private var openWindow
    @AppStorage("lastVideoQuality") private var lastVideoQuality = DownloadQuality.best.rawValue

    init(model: AppModel) {
        self.model = model
        self.settings = model.prefs
    }

    private var prefs: Preferences { model.prefs }
    private var toolchain: Toolchain { model.toolchain }
    private var hasLink: Bool { !model.trimmedURL.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                notice
                if hasLink {
                    linkStage
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    emptyStage
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 580)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: hasLink ? .top : .center) { length, _ in length }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(WindowBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let job = model.activeJob {
                NowDownloadingBar(job: job, remaining: model.pendingCount) { model.selection = .queue }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.35), value: hasLink)
        .animation(.smooth(duration: 0.3), value: model.displayedPreview)
        .animation(.smooth(duration: 0.25), value: prefs.quality)
        .animation(.smooth(duration: 0.3), value: model.activeJob?.id)
        .onAppear { urlFocused = true }
        .onChange(of: model.focusRequest) { urlFocused = true }
        .navigationTitle("Download")
    }

    // MARK: - Empty state

    private var emptyStage: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                AppGlyph(size: 76)
                    .padding(.bottom, 4)
                Text("My Videos")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.4)
                Text("Paste a link to save a video or a song.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if toolchain.hasChecked && !toolchain.isReady {
                setupPrompt
            } else {
                VStack(spacing: 14) {
                    linkField(large: true)
                    if model.clipboardHasLink {
                        HStack(spacing: 10) {
                            Text("You copied a link.")
                                .foregroundStyle(.secondary)
                            PasteButton(payloadType: String.self) { strings in
                                model.paste(strings.first)
                            }
                            .buttonBorderShape(.capsule)
                        }
                        .font(.callout)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }

            if !model.history.items.isEmpty {
                recentStrip
                    .padding(.top, 18)
            }

            footer
        }
        .animation(.smooth(duration: 0.25), value: model.clipboardHasLink)
    }

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("One more step")
                .font(.headline)
            Text("My Videos needs \(toolchain.missingTools.joined(separator: " and ")) to download.")
                .foregroundStyle(.secondary)
            Button("Finish Setup…") { model.showOnboarding = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recently Downloaded")
                    .font(.headline)
                Spacer()
                Button("Show All") { model.selection = .history }
                    .buttonStyle(.link)
                    .font(.callout)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(model.history.items.prefix(4)) { item in
                    RecentTile(item: item) { open(item) }
                }
                ForEach(0..<max(0, 4 - model.history.items.prefix(4).count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func open(_ item: HistoryItem) {
        let files = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let file = files.first else {
            model.selection = .history
            return
        }
        model.markPlayed([file])
        if MediaPlayer.canPlay(file) { openWindow(value: file) } else { NSWorkspace.shared.open(file) }
    }

    // MARK: - With a link

    private var linkStage: some View {
        VStack(spacing: 26) {
            linkField(large: false)
            hero
            controls
            footer
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch model.displayedPreview {
        case .loading, .empty:
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: 440)
                    .overlay { ProgressView() }
                VStack(spacing: 6) {
                    Text("Loading the title of this video")
                        .font(.title2.weight(.semibold))
                    Text("Channel name · 0:00")
                        .foregroundStyle(.secondary)
                }
                .redacted(reason: .placeholder)
            }
        case .loaded(let info):
            VStack(spacing: 16) {
                Thumbnail(url: info.thumbnailURL, isAudio: prefs.quality == .audio, cornerRadius: 16)
                    .frame(maxWidth: 440)
                    .overlay(alignment: .bottomTrailing) {
                        if let duration = info.duration, !info.isPlaylist {
                            Text(Timecode.string(duration))
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.6), in: Capsule())
                                .padding(10)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if info.isPlaylist {
                            Label("Playlist · \(info.playlistCount ?? 0) videos", systemImage: "list.bullet")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.6), in: Capsule())
                                .padding(10)
                        }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 22, y: 10)

                VStack(spacing: 6) {
                    Text(info.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text(heroSubtitle(info))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let link = model.subscribableLink, !model.subscriptions.contains(url: link) {
                            Button {
                                model.subscribeRequest = .init(link: link)
                            } label: {
                                Label("Follow", systemImage: "plus")
                                    .font(.callout.weight(.medium))
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .help("Download new uploads from \(info.uploader ?? "this channel") automatically")
                        }
                    }
                    if let existing = model.existingDownload(link: model.trimmedURL, info: info) {
                        duplicateNote(existing)
                            .padding(.top, 2)
                    }
                }
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "questionmark.video")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No Preview")
                    .font(.title3.weight(.semibold))
                Text("\(message) You can still try to download it.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
        }
    }

    private func heroSubtitle(_ info: MediaInfo) -> String {
        [info.uploader, info.site == "Youtube" ? "YouTube" : info.site].compactMap { $0 }.joined(separator: " · ")
    }

    private func duplicateNote(_ item: HistoryItem) -> some View {
        let files = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        return HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Downloaded \(item.date.formatted(date: .abbreviated, time: .omitted))")
                .foregroundStyle(.secondary)
            if !files.isEmpty {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(files) }
                    .buttonStyle(.link)
            }
        }
        .font(.callout)
    }

    // MARK: - Choices & download

    private enum Kind: Hashable { case video, audio }

    private var kind: Binding<Kind> {
        Binding {
            prefs.quality == .audio ? .audio : .video
        } set: { newValue in
            if newValue == .audio {
                if prefs.quality != .audio { lastVideoQuality = prefs.quality.rawValue }
                settings.quality = .audio
            } else {
                settings.quality = DownloadQuality(rawValue: lastVideoQuality).flatMap { $0 == .audio ? nil : $0 } ?? .best
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            Picker("Format", selection: kind) {
                Label("Video", systemImage: "film").tag(Kind.video)
                Label("Audio", systemImage: "music.note").tag(Kind.audio)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(width: 300)

            HStack(spacing: 8) {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    showOptions.toggle()
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.glass)
                .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                    DownloadOptionsPanel(model: model)
                }
            }
            .font(.callout)

            Button {
                model.downloadFromComposer()
            } label: {
                Text(model.activeJob == nil ? "Download" : "Add to Queue")
                    .font(.title3.weight(.semibold))
                    .frame(width: 240, height: 36)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.isValidURL || !toolchain.isReady)
        }
    }

    /// One line describing what will happen, e.g. "1080p · Subtitles · Clip 0:30–1:10".
    private var summary: String {
        var parts: [String] = []
        if prefs.quality == .audio {
            parts.append(prefs.audioFormat.displayName)
            if prefs.addToMusic && prefs.audioFormat.worksWithAppleMusic { parts.append("Adds to Apple Music") }
            if prefs.fetchLyrics && prefs.audioFormat.supportsArtwork { parts.append("Lyrics") }
        } else {
            parts.append(prefs.quality.displayName)
            if prefs.subtitles != .off { parts.append("\(prefs.subtitleLanguage.displayName) Subtitles") }
            if prefs.sponsorBlock == .remove { parts.append("No Sponsors") }
        }
        if model.downloadPlaylist {
            parts.append(model.playlistLimit > 0 ? "First \(model.playlistLimit)" : "Whole Playlist")
        }
        if model.clipEnabled {
            parts.append("Clip \(Timecode.string(model.clipStart))–\(Timecode.string(model.clipEnd))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Link field

    private func linkField(large: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: large ? 16 : 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Paste a video or playlist link", text: $model.urlString)
                .textFieldStyle(.plain)
                .font(large ? .title2 : .title3)
                .autocorrectionDisabled()
                .focused($urlFocused)
                .onSubmit { if model.isValidURL { model.downloadFromComposer() } }
                .accessibilityLabel("Video link")
            if model.preview == .loading {
                ProgressView().controlSize(.small)
            }
            if hasLink {
                Button {
                    model.urlString = ""
                    urlFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
                .accessibilityLabel("Clear link")
            } else {
                PasteButton(payloadType: String.self) { strings in
                    model.paste(strings.first)
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help("Paste Link")
            }
        }
        .padding(.horizontal, large ? 20 : 16)
        .frame(height: large ? 58 : 46)
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay(
            Capsule().strokeBorder(Color.accentColor.opacity(urlFocused ? 0.5 : 0), lineWidth: 1.5)
        )
        .animation(.smooth(duration: 0.2), value: urlFocused)
    }

    // MARK: - Footer & notices

    private var footer: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: prefs.destination.path))
                .resizable()
                .frame(width: 14, height: 14)
            Text("Saves to \(FileManager.default.displayName(atPath: prefs.destination.path))")
            Text("·").foregroundStyle(.tertiary)
            Text(signInSummary)
                .foregroundStyle(signInNeedsAttention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            SettingsLink { Text("Change").foregroundStyle(.tint) }
                .buttonStyle(.plain)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var signInNeedsAttention: Bool {
        if case .problem = model.signIn.state { return prefs.cookieSource != .none }
        return false
    }

    private var signInSummary: String {
        if signInNeedsAttention { return "Sign-in needs attention" }
        switch prefs.cookieSource {
        case .none: return "No sign-in"
        case .builtIn: return "Signed in with My Videos"
        case .browser: return "Signed in with \(prefs.cookieBrowser.displayName)"
        case .file: return "Using cookies.txt"
        }
    }

    /// At most one notice at a time, most important first.
    @ViewBuilder
    private var notice: some View {
        if Diagnostics.shared.hasNewCrash {
            NoticeBanner(systemImage: "exclamationmark.bubble.fill", tint: .orange,
                         title: "My Videos Quit Unexpectedly",
                         message: "A report was saved on this Mac.") {
                HStack(spacing: 8) {
                    Button("Dismiss") { Diagnostics.shared.markSeen() }
                        .buttonStyle(.glass)
                    Button("Save Report…") {
                        Diagnostics.shared.exportReport(activityLog: model.activityLog, toolchain: toolchain)
                        Diagnostics.shared.markSeen()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                }
            }
            .padding(.bottom, 24)
        } else if toolchain.updateAvailable {
            NoticeBanner(systemImage: "arrow.down.app.fill", tint: .blue,
                         title: "yt-dlp \(toolchain.latestYtdlpVersion ?? "") Is Available",
                         message: "Updating keeps downloads working as sites change.") {
                if toolchain.operation == .updating {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update") { Task { await toolchain.updateYtdlp(log: model.log) } }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Options panel

/// Everything beyond Video/Audio, in one tidy popover.
struct DownloadOptionsPanel: View {
    @Bindable var model: AppModel
    @Bindable private var settings: Preferences

    init(model: AppModel) {
        self.model = model
        self.settings = model.prefs
    }

    private var prefs: Preferences { model.prefs }

    var body: some View {
        Form {
            if prefs.quality == .audio {
                Section("Audio") {
                    Picker("Format", selection: $settings.audioFormat) {
                        ForEach(AudioFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Quality", selection: $settings.audioBitrate) {
                        ForEach(AudioBitrate.allCases) { Text($0.displayName).tag($0) }
                    }
                    .disabled(prefs.audioFormat == .wav)
                    Toggle("Even out volume", isOn: $settings.normalizeVolume)
                    Toggle("Find lyrics", isOn: $settings.fetchLyrics)
                        .disabled(!prefs.audioFormat.supportsArtwork)
                }
                Section {
                    Toggle("Add to Apple Music", isOn: $settings.addToMusic)
                        .disabled(!prefs.audioFormat.worksWithAppleMusic)
                    if prefs.addToMusic && prefs.audioFormat.worksWithAppleMusic {
                        if !model.downloadPlaylist {
                            TextField("Title", text: $model.tags.title, prompt: Text("Song title"))
                            TextField("Artist", text: $model.tags.artist, prompt: Text("Artist"))
                        }
                        TextField("Album", text: $model.tags.album, prompt: Text("Optional"))
                    }
                } header: {
                    Text("Apple Music")
                } footer: {
                    if !prefs.audioFormat.worksWithAppleMusic {
                        Text("Apple Music can’t play Opus files.").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Video") {
                    Picker("Quality", selection: $settings.quality) {
                        ForEach(DownloadQuality.allCases.filter { $0 != .audio }) { Text($0.displayName).tag($0) }
                    }
                    Picker("Subtitles", selection: $settings.subtitles) {
                        ForEach(SubtitleMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    if prefs.subtitles != .off {
                        Picker("Language", selection: $settings.subtitleLanguage) {
                            ForEach(SubtitleLanguage.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    Picker("Sponsored segments", selection: $settings.sponsorBlock) {
                        ForEach(SponsorBlockMode.allCases) { Text($0.displayName).tag($0) }
                    }
                }
            }

            if model.linkHasPlaylist {
                Section("Playlist") {
                    Toggle("Download the whole playlist", isOn: $model.downloadPlaylist)
                    if model.downloadPlaylist {
                        Picker("Videos", selection: $model.playlistLimit) {
                            Text("All").tag(0)
                            ForEach([5, 10, 25, 50, 100], id: \.self) { Text("First \($0)").tag($0) }
                        }
                    }
                }
            }

            if let duration = model.clipDuration, !model.downloadPlaylist {
                Section {
                    Toggle("Download only part", isOn: $model.clipEnabled)
                    if model.clipEnabled {
                        VStack(spacing: 10) {
                            RangeSlider(lower: $model.clipStart, upper: $model.clipEnd, bounds: 0...duration)
                            HStack {
                                TimecodeField(seconds: $model.clipStart, range: 0...max(model.clipEnd - 1, 0))
                                Spacer()
                                Text("\(Timecode.string(model.clipEnd - model.clipStart)) selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Spacer()
                                TimecodeField(seconds: $model.clipEnd, range: min(model.clipStart + 1, duration)...duration)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Clip")
                }
            }

            Section {
                Toggle("Cover art and details", isOn: $settings.embedArtwork)
            } footer: {
                Text("These choices are remembered for your next download.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .frame(minHeight: 260, maxHeight: 560)
    }
}

// MARK: - Pieces

private struct RecentTile: View {
    let item: HistoryItem
    let action: () -> Void
    @State private var hovering = false

    private var available: Bool { item.fileURLs.contains { FileManager.default.fileExists(atPath: $0.path) } }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Thumbnail(url: item.thumbnailURL, isAudio: item.isAudio, cornerRadius: 10)
                    .overlay {
                        if hovering && available {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.45), in: Circle())
                                .transition(.opacity)
                        }
                    }
                    .shadow(color: .black.opacity(hovering ? 0.2 : 0.08), radius: hovering ? 10 : 4, y: hovering ? 5 : 2)
                    .opacity(available ? 1 : 0.5)
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.18), value: hovering)
        .help(available ? "Play “\(item.title)”" : "This file has been moved or deleted")
    }
}

/// Pinned to the bottom of the Download page while something downloads.
struct NowDownloadingBar: View {
    let job: DownloadJob
    var remaining = 1
    let showQueue: () -> Void

    var body: some View {
        Button(action: showQueue) {
            HStack(spacing: 12) {
                Thumbnail(url: job.info?.thumbnailURL, isAudio: job.options.isAudio, cornerRadius: 5)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.displayTitle)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        if remaining > 1 {
                            Text("\(remaining) in queue")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    JobProgressBar(job: job)
                    Text(job.statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: 580)
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
        .help("Show Queue")
    }
}

struct JobProgressBar: View {
    let job: DownloadJob

    var body: some View {
        Group {
            if job.progressIsIndeterminate {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
            }
        }
        .controlSize(.small)
        .tint(job.phase == .processing ? .orange : .accentColor)
    }
}
