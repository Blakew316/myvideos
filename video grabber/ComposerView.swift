//
//  ComposerView.swift
//  My Videos
//

import SwiftUI
import AppKit

/// The Download page: paste a link, see what it is, choose how to save it.
struct ComposerView: View {
    @Bindable var model: AppModel
    @Bindable private var settings: Preferences
    @FocusState private var urlFocused: Bool

    init(model: AppModel) {
        self.model = model
        self.settings = model.prefs
    }

    private var prefs: Preferences { model.prefs }
    private var toolchain: Toolchain { model.toolchain }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                linkBar
                banners
                if model.displayedPreview != .empty {
                    PreviewCard(state: model.displayedPreview, isAudio: prefs.quality == .audio)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
                formatCard
                if model.linkHasPlaylist { playlistCard }
                if model.clipDuration != nil && !model.downloadPlaylist { clipCard }
                if prefs.quality == .audio { musicCard }
                saveCard
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(WindowBackdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let job = model.activeJob {
                NowDownloadingBar(job: job) { model.selection = .queue }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: model.displayedPreview)
        .animation(.smooth(duration: 0.3), value: prefs.quality)
        .animation(.smooth(duration: 0.3), value: model.linkHasPlaylist)
        .animation(.smooth(duration: 0.3), value: model.downloadPlaylist)
        .animation(.smooth(duration: 0.3), value: model.clipEnabled)
        .animation(.smooth(duration: 0.3), value: model.clipboardHasLink)
        .animation(.smooth(duration: 0.3), value: toolchain.updateAvailable)
        .animation(.smooth(duration: 0.3), value: model.activeJob?.id)
        .onAppear { urlFocused = true }
        .onChange(of: model.focusRequest) { urlFocused = true }
        .navigationTitle("Download")
    }

    // MARK: - Header & link

    private var header: some View {
        VStack(spacing: 10) {
            AppGlyph(size: 60)
            VStack(spacing: 3) {
                Text("My Videos")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.3)
                Text("Save videos and music from across the web.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var linkBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Paste a video or playlist link", text: $model.urlString)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .autocorrectionDisabled()
                    .focused($urlFocused)
                    .onSubmit { if model.isValidURL { model.downloadFromComposer() } }
                    .accessibilityLabel("Video link")
                if model.preview == .loading {
                    ProgressView().controlSize(.small)
                }
                if !model.urlString.isEmpty {
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
            .padding(.horizontal, 16)
            .frame(height: 46)
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay(
                Capsule().strokeBorder(Color.accentColor.opacity(urlFocused ? 0.55 : 0), lineWidth: 1.5)
            )
            .animation(.smooth(duration: 0.2), value: urlFocused)

            Button {
                model.downloadFromComposer()
            } label: {
                Label(model.activeJob == nil ? "Download" : "Add to Queue",
                      systemImage: model.activeJob == nil ? "arrow.down" : "text.badge.plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 6)
                    .frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.isValidURL || !toolchain.isReady)
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var banners: some View {
        if toolchain.hasChecked && !toolchain.isReady {
            NoticeBanner(systemImage: "wrench.and.screwdriver.fill", tint: .orange,
                         title: "Finish Setting Up",
                         message: "My Videos needs \(toolchain.missingTools.joined(separator: " and ")) to download.") {
                Button("Set Up…") { model.showOnboarding = true }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
            }
        } else if toolchain.updateAvailable {
            NoticeBanner(systemImage: "arrow.down.app.fill", tint: .blue,
                         title: "Update Available",
                         message: "yt-dlp \(toolchain.latestYtdlpVersion ?? "") keeps downloads working as sites change.") {
                if toolchain.operation == .updating {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update") {
                        Task { await toolchain.updateYtdlp(log: model.log) }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }

        if model.clipboardHasLink && model.urlString.isEmpty {
            NoticeBanner(systemImage: "doc.on.clipboard.fill", tint: .accentColor,
                         title: "You Copied a Link",
                         message: "Download it with My Videos?") {
                HStack(spacing: 8) {
                    Button("Not Now") { model.dismissClipboardSuggestion() }
                        .buttonStyle(.glass)
                    PasteButton(payloadType: String.self) { strings in
                        model.paste(strings.first)
                    }
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }

    // MARK: - Cards

    private var formatCard: some View {
        FormCard(title: "Format") {
            FormRow(title: "Quality", systemImage: "sparkles.tv", color: .purple) {
                Picker("Quality", selection: $settings.quality) {
                    ForEach(DownloadQuality.allCases) { q in
                        Label(q.rawValue, systemImage: q.symbol).tag(q)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if prefs.quality == .audio {
                FormRow(title: "Audio Format", systemImage: "waveform", color: .pink,
                        detail: prefs.audioFormat == .opus ? "Opus files can’t be added to Apple Music." : nil) {
                    Picker("Audio Format", selection: $settings.audioFormat) {
                        ForEach(AudioFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                FormRow(title: "Bitrate", systemImage: "dial.medium", color: .orange) {
                    Picker("Bitrate", selection: $settings.audioBitrate) {
                        ForEach(AudioBitrate.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(prefs.audioFormat == .wav)
                }
            } else {
                FormRow(title: "Subtitles", systemImage: "captions.bubble.fill", color: .teal) {
                    HStack(spacing: 8) {
                        if prefs.subtitles != .off {
                            Picker("Language", selection: $settings.subtitleLanguage) {
                                ForEach(SubtitleLanguage.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Picker("Subtitles", selection: $settings.subtitles) {
                            ForEach(SubtitleMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            FormRow(title: "Cover Art & Details", systemImage: "photo.fill", color: .indigo,
                    detail: "Adds the thumbnail, title and channel to the file.") {
                Toggle("Cover Art & Details", isOn: $settings.embedArtwork)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var playlistCard: some View {
        FormCard(title: "Playlist") {
            FormRow(title: "Download Entire Playlist", systemImage: "list.and.film", color: .red,
                    detail: playlistDetail) {
                Toggle("Download Entire Playlist", isOn: $model.downloadPlaylist)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if model.downloadPlaylist {
                FormRow(title: "Limit", systemImage: "number", color: .gray) {
                    Picker("Limit", selection: $model.playlistLimit) {
                        Text("All Videos").tag(0)
                        ForEach([5, 10, 25, 50, 100], id: \.self) { Text("First \($0)").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private var playlistDetail: String {
        if case .loaded(let info) = model.displayedPreview, info.isPlaylist, let count = info.playlistCount {
            return "\(info.title) · \(count) video\(count == 1 ? "" : "s")"
        }
        return "Saves into a folder named after the playlist."
    }

    private var clipCard: some View {
        let duration = model.clipDuration ?? 1
        return FormCard(title: "Clip",
                        footer: model.clipEnabled ? "Only the selected part is downloaded — \(Timecode.string(model.clipEnd - model.clipStart)) in total." : nil) {
            FormRow(title: "Download Only Part", systemImage: "scissors", color: .yellow) {
                Toggle("Download Only Part", isOn: $model.clipEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if model.clipEnabled {
                VStack(spacing: 12) {
                    RangeSlider(lower: $model.clipStart, upper: $model.clipEnd, bounds: 0...duration)
                    HStack {
                        TimecodeField(seconds: $model.clipStart, range: 0...max(model.clipEnd - 1, 0))
                        Spacer()
                        Text(Timecode.string(duration))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Spacer()
                        TimecodeField(seconds: $model.clipEnd, range: min(model.clipStart + 1, duration)...duration)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private var musicCard: some View {
        FormCard(title: "Apple Music",
                 footer: model.downloadPlaylist ? "Each song keeps its own title and artist." : nil) {
            FormRow(title: "Add to Apple Music", systemImage: "music.note", color: .pink,
                    detail: prefs.audioFormat.worksWithAppleMusic ? nil : "Not available for Opus.") {
                Toggle("Add to Apple Music", isOn: $settings.addToMusic)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!prefs.audioFormat.worksWithAppleMusic)
            }
            if prefs.addToMusic && prefs.audioFormat.worksWithAppleMusic {
                if !model.downloadPlaylist {
                    tagRow("Title", "music.quarternote.3", .red, text: $model.tags.title, prompt: "Song title")
                    tagRow("Artist", "music.mic", .orange, text: $model.tags.artist, prompt: "Artist")
                }
                tagRow("Album", "square.stack.fill", .purple, text: $model.tags.album, prompt: "Optional")
            }
        }
    }

    private func tagRow(_ title: String, _ icon: String, _ color: Color,
                        text: Binding<String>, prompt: String) -> some View {
        FormRow(title: title, systemImage: icon, color: color) {
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 300)
        }
    }

    private var saveCard: some View {
        FormCard(title: "Save") {
            FormRow(title: "Save To", systemImage: "folder.fill", color: .blue) {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: prefs.destination.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(FileManager.default.displayName(atPath: prefs.destination.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(prefs.destination.path)
                    Button("Choose…", action: chooseFolder)
                }
            }
            FormRow(title: "Sign-In", systemImage: "person.crop.circle.badge.checkmark", color: .green) {
                HStack(spacing: 8) {
                    Picker("Sign-In", selection: $settings.cookieSource) {
                        ForEach(CookieSource.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    SettingsLink {
                        Text("Manage…")
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = prefs.destination
        if panel.runModal() == .OK, let url = panel.url {
            settings.destination = url
        }
    }
}

// MARK: - Preview card

struct PreviewCard: View {
    let state: AppModel.PreviewState
    let isAudio: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if case .loaded(let info) = state {
                    Thumbnail(url: info.thumbnailURL, isAudio: isAudio, cornerRadius: 10)
                        .overlay(alignment: .bottomTrailing) { durationBadge(info) }
                } else {
                    Thumbnail(url: nil, isAudio: isAudio, cornerRadius: 10)
                }
            }
            .frame(width: 168)

            VStack(alignment: .leading, spacing: 6) {
                switch state {
                case .loading:
                    Text("Loading the video’s title and artwork")
                        .font(.headline)
                        .redacted(reason: .placeholder)
                    Text("Channel name")
                        .redacted(reason: .placeholder)
                    ProgressView().controlSize(.small).padding(.top, 2)
                case .loaded(let info):
                    Text(info.title)
                        .font(.headline)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    if let uploader = info.uploader {
                        Text(uploader)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if info.isPlaylist {
                            Tag(text: "Playlist", systemImage: "list.bullet", tint: .red)
                            if let count = info.playlistCount {
                                Tag(text: "\(count) videos", systemImage: nil, tint: .secondary)
                            }
                        }
                        if info.isLive {
                            Tag(text: "Live", systemImage: "dot.radiowaves.left.and.right", tint: .red)
                        }
                        if let site = info.site {
                            Tag(text: site, systemImage: nil, tint: .secondary)
                        }
                    }
                    .padding(.top, 2)
                case .failed(let message):
                    Label("Preview Unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("\(message) You can still try downloading it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .empty:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func durationBadge(_ info: MediaInfo) -> some View {
        if let duration = info.duration, !info.isPlaylist {
            Text(Timecode.string(duration))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
        }
    }
}

struct Tag: View {
    let text: String
    let systemImage: String?
    let tint: Color

    var body: some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Now downloading bar

/// Pinned to the bottom of the Download page while something is downloading.
struct NowDownloadingBar: View {
    let job: DownloadJob
    let showQueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: job.info?.thumbnailURL, isAudio: job.options.isAudio, cornerRadius: 5)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                JobProgressBar(job: job)
                Text(job.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Button("Show Queue", action: showQueue)
                .buttonStyle(.glass)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: 640)
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
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
