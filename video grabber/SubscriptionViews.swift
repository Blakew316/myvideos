//
//  SubscriptionViews.swift
//  My Videos
//

import SwiftUI
import AppKit

// MARK: - Avatar

/// A round channel picture, falling back to the channel's initial on a soft gradient.
struct ChannelAvatar: View {
    let url: URL?
    let title: String
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Brand.indigo.opacity(0.85), Brand.indigo.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
            Text(String(title.first ?? "•").uppercased())
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityHidden(true)
    }
}

// MARK: - Overview

struct SubscriptionsOverview: View {
    @Bindable var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)]

    var body: some View {
        Group {
            if model.subscriptions.items.isEmpty {
                ContentUnavailableView {
                    Label("No Subscriptions", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Follow a channel or playlist and My Videos downloads new uploads automatically.")
                } actions: {
                    Button("Add Subscription…") { model.subscribeRequest = .init(link: "") }
                        .buttonStyle(.glassProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.subscriptions.items) { sub in
                            Button {
                                model.selection = .subscription(sub.id)
                            } label: {
                                SubscriptionCard(subscription: sub, isChecking: model.checkingSubscriptions.contains(sub.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(WindowBackdrop())
        .navigationTitle("Subscriptions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.checkAllSubscriptions(onlyDue: false) }
                } label: {
                    Label("Check All Now", systemImage: "arrow.clockwise")
                }
                .help("Check every subscription for new uploads")
                .disabled(model.subscriptions.items.isEmpty || !model.checkingSubscriptions.isEmpty)
                Button {
                    model.subscribeRequest = .init(link: "")
                } label: {
                    Label("Add Subscription", systemImage: "plus")
                }
                .help("Add Subscription")
            }
        }
    }
}

private struct SubscriptionCard: View {
    let subscription: Subscription
    let isChecking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ChannelAvatar(url: subscription.avatarURL, title: subscription.title, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(subscription.lastError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if subscription.unseenCount > 0 {
                    Text("\(subscription.unseenCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            HStack(spacing: 6) {
                ForEach(subscription.recent.prefix(3)) { entry in
                    Thumbnail(url: entry.thumbnailURL, cornerRadius: 5)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16, style: .continuous))
        .opacity(subscription.isEnabled ? 1 : 0.6)
        .contentShape(Rectangle())
    }

    private var statusLine: String {
        if isChecking { return "Checking…" }
        if !subscription.isEnabled { return "Paused" }
        if let error = subscription.lastError { return error }
        return "\(subscription.formatDescription) · checked \(subscription.lastChecked?.formatted(.relative(presentation: .named)) ?? "never")"
    }
}

// MARK: - Detail

struct SubscriptionDetailView: View {
    @Bindable var model: AppModel
    let id: UUID
    @State private var confirmRemove = false

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18)]

    var body: some View {
        if let sub = model.subscriptions.subscription(id: id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(sub)
                    settingsCard(sub)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Uploads")
                            .font(.title3.weight(.semibold))
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(sub.recent) { entry in
                                UploadCard(entry: entry,
                                           state: state(of: entry, in: sub)) {
                                    model.download(entry, from: sub)
                                }
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(WindowBackdrop())
            .navigationTitle(sub.title)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await model.checkSubscription(id) }
                    } label: {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                    .help("Check for new uploads now")
                    .disabled(model.checkingSubscriptions.contains(id))
                    Menu {
                        if let url = URL(string: sub.url) {
                            Button("Open in Browser") { NSWorkspace.shared.open(url) }
                        }
                        Button("Show Downloads Folder") {
                            let folder = model.prefs.destination.appendingPathComponent(sub.title)
                            NSWorkspace.shared.open(FileManager.default.fileExists(atPath: folder.path) ? folder : model.prefs.destination)
                        }
                        Divider()
                        Button("Unsubscribe…", role: .destructive) { confirmRemove = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Unsubscribe from \(sub.title)?", isPresented: $confirmRemove) {
                Button("Unsubscribe", role: .destructive) { model.unsubscribe(id) }
            } message: {
                Text("New uploads will stop downloading. Files you already have aren’t affected.")
            }
            .onAppear { model.markViewed(id) }
            .onChange(of: sub.unseenCount) { model.markViewed(id) }
        } else {
            ContentUnavailableView("Subscription Not Found", systemImage: "questionmark.circle")
        }
    }

    private func header(_ sub: Subscription) -> some View {
        HStack(spacing: 18) {
            ChannelAvatar(url: sub.avatarURL, title: sub.title, size: 76)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(sub.title)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                Group {
                    if model.checkingSubscriptions.contains(sub.id) {
                        Label("Checking for new uploads…", systemImage: "arrow.clockwise")
                    } else if let error = sub.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else if let last = sub.lastChecked {
                        Text("Checked \(last.formatted(.relative(presentation: .named))) · \(sub.downloadedIDs.count) downloaded")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func settingsCard(_ sub: Subscription) -> some View {
        FormCard {
            FormRow(title: "Download New Uploads", systemImage: "arrow.down.circle.fill", color: .blue,
                    detail: "Checks every \(intervalText) while My Videos is open.") {
                Toggle("Download New Uploads", isOn: binding(sub, \.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            FormRow(title: "Format", systemImage: "sparkles.tv", color: .purple) {
                Picker("Format", selection: formatBinding(sub)) {
                    ForEach(DownloadQuality.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if sub.isAudio {
                FormRow(title: "Add to Apple Music", systemImage: "music.note", color: .pink) {
                    Toggle("Add to Apple Music", isOn: binding(sub, \.addToMusic))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        .frame(maxWidth: 560)
    }

    private var intervalText: String {
        let minutes = model.prefs.subscriptionInterval
        switch minutes {
        case ..<60: return "\(minutes) minutes"
        case 60: return "hour"
        case 1440: return "day"
        default: return "\(minutes / 60) hours"
        }
    }

    private func binding(_ sub: Subscription, _ keyPath: WritableKeyPath<Subscription, Bool>) -> Binding<Bool> {
        Binding {
            model.subscriptions.subscription(id: sub.id)?[keyPath: keyPath] ?? false
        } set: { value in
            model.subscriptions.updateChoices(sub.id) { $0[keyPath: keyPath] = value }
        }
    }

    private func formatBinding(_ sub: Subscription) -> Binding<DownloadQuality> {
        Binding {
            let current = model.subscriptions.subscription(id: sub.id) ?? sub
            return current.isAudio ? .audio : current.quality
        } set: { value in
            model.subscriptions.updateChoices(sub.id) {
                $0.isAudio = value == .audio
                if value != .audio { $0.quality = value }
            }
        }
    }

    private func state(of entry: FeedEntry, in sub: Subscription) -> UploadCard.State {
        if sub.downloadedIDs.contains(entry.id) { return .downloaded }
        if model.jobs.contains(where: { $0.feedEntryID == entry.id && !$0.isDone }) { return .downloading }
        return .available
    }
}

private struct UploadCard: View {
    enum State { case available, downloading, downloaded }

    let entry: FeedEntry
    let state: State
    let download: () -> Void
    @SwiftUI.State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumbnail(url: entry.thumbnailURL, cornerRadius: 10)
                .overlay(alignment: .bottomTrailing) {
                    if let duration = entry.duration {
                        Text(Timecode.string(duration))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
                .overlay {
                    if state == .available && hovering {
                        Button(action: download) {
                            Label("Download", systemImage: "arrow.down")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.glassProminent)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .scaleEffect(hovering ? 1.02 : 1)
                .shadow(color: .black.opacity(hovering ? 0.18 : 0.06), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
            HStack(alignment: .top, spacing: 6) {
                Text(entry.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
                switch state {
                case .downloaded:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Downloaded")
                case .downloading:
                    ProgressView().controlSize(.small).help("Downloading")
                case .available:
                    EmptyView()
                }
            }
        }
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
        .contextMenu {
            if state == .available { Button("Download", action: download) }
            if let url = URL(string: entry.url) {
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url, forType: .string)
                }
            }
        }
    }
}

// MARK: - Subscribe sheet

struct SubscribeSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var link: String
    @State private var state: LoadState = .idle
    @State private var format: DownloadQuality = .best
    @State private var addToMusic = true
    @State private var downloadLatest = 0
    @State private var task: Task<Void, Never>?

    enum LoadState: Equatable {
        case idle, loading, loaded(Feed), failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "dot.radiowaves.left.and.right", color: .red, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Subscription").font(.title2.weight(.bold))
                        Text("New uploads download automatically.")
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Channel or playlist link", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(load)
                    .onChange(of: link) { scheduleLoad() }

                preview
                    .animation(.smooth(duration: 0.3), value: state)

                if case .loaded = state {
                    FormCard {
                        FormRow(title: "Format", systemImage: "sparkles.tv", color: .purple) {
                            Picker("Format", selection: $format) {
                                ForEach(DownloadQuality.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        if format == .audio {
                            FormRow(title: "Add to Apple Music", systemImage: "music.note", color: .pink) {
                                Toggle("Add to Apple Music", isOn: $addToMusic).labelsHidden().toggleStyle(.switch)
                            }
                        }
                        FormRow(title: "Right Now", systemImage: "clock.fill", color: .orange) {
                            Picker("Right Now", selection: $downloadLatest) {
                                Text("Only Future Uploads").tag(0)
                                Text("Also the Latest 1").tag(1)
                                Text("Also the Latest 3").tag(3)
                                Text("Also the Latest 5").tag(5)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(24)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Subscribe", action: subscribe)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubscribe)
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.smooth(duration: 0.3), value: state)
        .background(WindowBackdrop())
        .onAppear {
            format = model.prefs.quality
            addToMusic = model.prefs.addToMusic
            if !link.isEmpty { load() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch state {
        case .idle:
            Text("Paste a link to a YouTube channel (like youtube.com/@name) or any playlist.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking up the channel…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded(let feed):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ChannelAvatar(url: feed.avatarURL, title: feed.title, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feed.title).font(.headline)
                        Text(alreadySubscribed ? "You’re already subscribed." : "Latest: \(feed.entries.first?.title ?? "")")
                            .font(.caption)
                            .foregroundStyle(alreadySubscribed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(feed.entries.prefix(4)) { entry in
                        Thumbnail(url: entry.thumbnailURL, cornerRadius: 6)
                    }
                }
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
        }
    }

    private var alreadySubscribed: Bool { model.subscriptions.contains(url: link) }

    private var canSubscribe: Bool {
        if case .loaded = state { return !alreadySubscribed }
        return false
    }

    private func scheduleLoad() {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            load()
        }
    }

    private func load() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppModel.isWebLink(trimmed) else {
            state = trimmed.isEmpty ? .idle : .failed("Paste a link that starts with https://")
            return
        }
        state = .loading
        Task {
            let result = await model.fetchFeed(trimmed)
            guard link.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            switch result {
            case .success(let feed): state = .loaded(feed)
            case .failure(let message): state = .failed(message)
            }
        }
    }

    private func subscribe() {
        guard case .loaded(let feed) = state else { return }
        model.subscribe(link: link.trimmingCharacters(in: .whitespacesAndNewlines), feed: feed,
                        isAudio: format == .audio, quality: format, addToMusic: addToMusic,
                        downloadLatest: downloadLatest)
        dismiss()
    }
}
