//
//  AddLinkBar.swift
//  My Videos
//
//  Adding is a quick action, not a destination: a link bar at the top of Home drops down
//  a card to confirm, and a Downloads button in the toolbar tracks activity.
//

import SwiftUI
import AppKit

// MARK: - Link bar

struct AddLinkField: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    @State private var hovering = false

    /// The card appears once the link has been looked up — never mid-typing.
    private var cardPresented: Binding<Bool> {
        Binding {
            guard model.isValidURL, model.addCardDismissedFor != model.trimmedURL else { return false }
            switch model.preview {
            case .loaded, .failed: return true
            default: return false
            }
        } set: { shown in
            if !shown { model.addCardDismissedFor = model.trimmedURL }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if model.preview == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(focused ? Color.accentColor : .secondary)
                }
            }
            .frame(width: 22)
            TextField("Paste a link to a video, playlist or song", text: $model.urlString)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(submit)
                .accessibilityLabel("Link to download")
            if !model.urlString.isEmpty {
                Button {
                    model.urlString = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
            Button(model.urlString.isEmpty ? "Paste" : "Download", action: primaryAction)
                .buttonStyle(PrimaryCapsuleButtonStyle(height: 34))
            .disabled(!model.urlString.isEmpty && !model.isValidURL)
            .help(model.urlString.isEmpty ? "Paste a copied link" : "Download this link")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 50)
        .frame(maxWidth: 680)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay(
            Capsule().strokeBorder(focused ? Color.accentColor.opacity(0.65) : Color.primary.opacity(hovering ? 0.14 : 0.08),
                                   lineWidth: focused ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(focused ? 0.14 : 0.07), radius: focused ? 18 : 10, y: 4)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: focused)
        .popover(isPresented: cardPresented, arrowEdge: .bottom) {
            AddCard(model: model)
        }
        .task(id: model.focusRequest) {
            // The field may appear after New Download (⌘N) was chosen elsewhere.
            if model.focusRequest != model.focusHandled {
                model.focusHandled = model.focusRequest
                focused = true
            }
        }
        .onChange(of: model.urlString) { if model.urlString.isEmpty { model.addCardDismissedFor = nil } }
    }

    private func submit() {
        guard model.isValidURL else { return }
        model.addCardDismissedFor = nil
        if case .loaded = model.preview { model.downloadFromComposer() }
    }

    private func primaryAction() {
        if model.urlString.isEmpty {
            model.pasteFromClipboard()
        } else {
            submit()
        }
    }
}

// MARK: - Add card

/// Confirms a download: what it is, Video or Audio, optional details, Download.
struct AddCard: View {
    @Bindable var model: AppModel
    @Bindable private var settings: Preferences
    @State private var showOptions = false
    @AppStorage("lastVideoQuality") private var lastVideoQuality = DownloadQuality.best.rawValue

    init(model: AppModel) {
        self.model = model
        self.settings = model.prefs
    }

    private var prefs: Preferences { model.prefs }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Picker("Format", selection: kind) {
                Label("Video", systemImage: "film").tag(Kind.video)
                Label("Audio", systemImage: "music.note").tag(Kind.audio)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.smooth(duration: 0.25)) { showOptions.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(showOptions ? 90 : 0))
                        Text("Options")
                            .fontWeight(.medium)
                        Text(summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)

                if showOptions {
                    DownloadOptionsPanel(model: model, embedded: true)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            HStack(spacing: 10) {
                signInNote
                Spacer()
                Button("Cancel") { model.addCardDismissedFor = model.trimmedURL }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button {
                    model.downloadFromComposer()
                } label: {
                    Text(model.activeJob == nil ? "Download" : "Add to Downloads")
                }
                .buttonStyle(PrimaryCapsuleButtonStyle(height: 32))
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isValidURL || !model.toolchain.isReady)
            }
        }
        .padding(20)
        .frame(width: 440)
        .animation(.smooth(duration: 0.25), value: prefs.quality)
    }

    @ViewBuilder
    private var header: some View {
        switch model.displayedPreview {
        case .loaded(let info):
            VStack(alignment: .leading, spacing: 12) {
                Thumbnail(url: info.thumbnailURL, isAudio: prefs.quality == .audio, cornerRadius: 14)
                    .frame(width: 400, height: 225)
                    .overlay(alignment: .bottomTrailing) {
                        if let duration = info.duration, !info.isPlaylist {
                            Text(Timecode.string(duration))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.black.opacity(0.6), in: Capsule())
                                .padding(10)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if info.isPlaylist {
                            Label("Playlist · \(info.playlistCount ?? 0)", systemImage: "square.stack.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.6), in: Capsule())
                                .padding(10)
                        }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text(info.uploader ?? info.site ?? "")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let existing = model.existingDownload(link: model.trimmedURL, info: info) {
                            Label("In Your Library", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Brand.sage)
                                .help("Downloaded \(existing.date.formatted(date: .abbreviated, time: .shortened))")
                        }
                        if let link = model.subscribableLink, !model.subscriptions.contains(url: link) {
                            Button {
                                model.addCardDismissedFor = model.trimmedURL
                                model.subscribeRequest = .init(link: link)
                            } label: {
                                Label("Follow", systemImage: "plus")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .help("Download new uploads from \(info.uploader ?? "this channel") automatically")
                        }
                    }
                    .font(.callout)
                }
            }
        case .failed(let message):
            HStack(spacing: 12) {
                Image(systemName: "questionmark.video")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No Preview").font(.headline)
                    Text("\(message) You can still try to download it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        default:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking up this link…").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var signInNote: some View {
        if prefs.cookieSource != .none {
            let needsAttention: Bool = { if case .problem = model.signIn.state { return true }; return false }()
            Label(needsAttention ? "Sign-in needs attention" : "Signed in",
                  systemImage: needsAttention ? "exclamationmark.triangle.fill" : "person.crop.circle.badge.checkmark")
                .font(.caption)
                .foregroundStyle(needsAttention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .help(needsAttention ? "Open Settings → Accounts to fix sign-in" : "Using your \(prefs.cookieSource.displayName)")
        }
    }

    private var summary: String {
        var parts: [String] = []
        if prefs.quality == .audio {
            parts.append(prefs.audioFormat == .m4a ? "AAC" : prefs.audioFormat.displayName)
            if prefs.addToMusic && prefs.audioFormat.worksWithAppleMusic { parts.append("Apple Music") }
            if prefs.fetchLyrics && prefs.audioFormat.supportsArtwork { parts.append("Lyrics") }
        } else {
            parts.append(prefs.quality.displayName)
            if prefs.subtitles != .off { parts.append("Subtitles") }
            if prefs.sponsorBlock == .remove { parts.append("No Sponsors") }
        }
        if model.downloadPlaylist { parts.append(model.playlistLimit > 0 ? "First \(model.playlistLimit)" : "Whole Playlist") }
        if model.clipEnabled { parts.append("Clip \(Timecode.string(model.clipStart))–\(Timecode.string(model.clipEnd))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Downloads button (Safari-style)

struct DownloadsToolbarButton: View {
    @Bindable var model: AppModel

    private var active: [DownloadJob] { model.activeJobs }
    private var progress: Double? {
        let known = active.filter { !$0.progressIsIndeterminate }
        guard !known.isEmpty else { return nil }
        return active.map { $0.progressIsIndeterminate ? 0 : $0.progress }.reduce(0, +) / Double(active.count)
    }

    var body: some View {
        Button {
            model.showDownloads.toggle()
        } label: {
            HStack(spacing: 0) {
            ZStack {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                Circle()
                    .stroke(Color.primary.opacity(active.isEmpty ? 0.6 : 0.18), lineWidth: 1.6)
                if let progress, !active.isEmpty {
                    Circle()
                        .trim(from: 0, to: max(0.03, progress))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.4), value: progress)
                }
            }
            .frame(width: 17, height: 17)
            .overlay(alignment: .topTrailing) {
                if model.pendingCount > 1 {
                    Text("\(model.pendingCount)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(Color.accentColor))
                        .offset(x: 9, y: -7)
                }
            }
            }
        }
        .help("Downloads")
        .accessibilityLabel("Downloads")
        .accessibilityValue(model.pendingCount == 0 ? "None in progress" : "\(model.pendingCount) in progress")
        .popover(isPresented: $model.showDownloads, arrowEdge: .bottom) {
            DownloadsPopover(model: model)
        }
    }
}

struct DownloadsPopover: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                if model.pausedCount > 0 && model.pendingCount == 0 {
                    Button("Resume All") { model.resumeAll() }
                } else if model.pendingCount > 0 {
                    Button("Pause All") { model.pauseAll() }
                }
                if model.jobs.contains(where: \.isDone) {
                    Button("Clear") { model.clearFinished() }
                }
            }
            .buttonStyle(.link)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            if model.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No Downloads").font(.headline)
                    Text("Paste a link in the toolbar to start one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.jobs.reversed()) { job in
                            JobRow(job: job, model: model)
                                .padding(.horizontal, 14)
                            Divider().padding(.leading, 124)
                        }
                    }
                }
                .frame(maxHeight: 440)
            }
        }
        .frame(width: 440)
    }
}


// MARK: - Options panel

/// Everything beyond Video/Audio, in one tidy popover.
struct DownloadOptionsPanel: View {
    @Bindable var model: AppModel
    @Bindable private var settings: Preferences
    /// Shown inside the add card rather than in its own popover.
    var embedded = false

    init(model: AppModel, embedded: Bool = false) {
        self.model = model
        self.settings = model.prefs
        self.embedded = embedded
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
        .frame(width: embedded ? nil : 400)
        .frame(minHeight: embedded ? nil : 260, maxHeight: embedded ? nil : 560)
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
