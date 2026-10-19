//
//  LibraryView.swift
//  My Videos
//
//  The heart of the app: everything you've saved, as artwork. Downloads in progress
//  appear right here too, with a progress ring over their artwork.
//

import SwiftUI
import AppKit
import QuickLook
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: AppModel
    let filter: LibraryFilter

    @State private var search = ""
    @State private var selection = Set<HistoryItem.ID>()
    @State private var quickLookURL: URL?
    @State private var pendingRemoval: Set<HistoryItem.ID> = []
    @State private var isDropTargeted = false
    @FocusState private var gridFocused: Bool
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.adaptive(minimum: 208, maximum: 290), spacing: 22, alignment: .top)]

    // MARK: Data

    private var items: [HistoryItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return model.history.items.filter { item in
            guard filter.includes(isAudio: item.isAudio) else { return false }
            guard !query.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(query)
                || (item.uploader?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var pending: [DownloadJob] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return model.pendingJobs.filter { job in
            filter.includes(isAudio: job.options.isAudio)
                && (query.isEmpty || job.displayTitle.localizedCaseInsensitiveContains(query))
        }
    }

    private struct ItemGroup: Identifiable {
        let id: String
        let title: String
        var items: [HistoryItem]
    }

    private var groups: [ItemGroup] {
        var order: [String] = []
        var byKey: [String: [HistoryItem]] = [:]
        for item in items {
            let key = model.libraryGrouping == .date ? Self.dateBucket(item.date) : (item.uploader ?? "Other")
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(item)
        }
        return order.map { ItemGroup(id: $0, title: $0, items: byKey[$0] ?? []) }
    }

    private static func dateBucket(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return "This Week" }
        if days < 31 { return "This Month" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    // MARK: Body

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                // The one thing people come here to do, always in reach.
                HStack { AddLinkField(model: model) }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
            }
            .background(WindowBackdrop())
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .padding(10)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .navigationTitle(filter.title)
            .navigationSubtitle(subtitle)
            .searchable(text: $search, placement: .sidebar, prompt: "Search Library")
            // ⌘V anywhere in the library starts a download from the copied link.
            .onPasteCommand(of: [.url, .plainText]) { _ in
                model.pasteFromClipboard()
            }
            .dropDestination(for: URL.self) { urls, _ in
                if let web = urls.first(where: { !$0.isFileURL }) {
                    model.paste(web.absoluteString)
                    return true
                }
                let files = urls.filter(\.isFileURL)
                if !files.isEmpty { model.stage(files); return true }
                return false
            } isTargeted: { isDropTargeted = $0 }
            .quickLookPreview($quickLookURL, in: files(of: selection))
            .onChange(of: quickLookURL) { if let url = quickLookURL { model.markPlayed([url]) } }
            .confirmationDialog(removalTitle, isPresented: Binding(
                get: { !pendingRemoval.isEmpty }, set: { if !$0 { pendingRemoval = [] } })) {
                Button("Remove from Library", role: .destructive) {
                    model.history.remove(ids: pendingRemoval)
                    selection.subtract(pendingRemoval)
                    pendingRemoval = []
                }
                Button("Move to Trash", role: .destructive) {
                    for file in files(of: pendingRemoval) { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
                    model.history.remove(ids: pendingRemoval)
                    selection.subtract(pendingRemoval)
                    pendingRemoval = []
                }
            } message: {
                Text("“Remove from Library” keeps the files on your Mac.")
            }
            .animation(.smooth(duration: 0.35), value: model.pendingJobs.map(\.id))
            .animation(.smooth(duration: 0.35), value: model.history.items.map(\.id))
            .animation(.smooth(duration: 0.25), value: isDropTargeted)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty && pending.isEmpty {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if model.history.items.isEmpty && model.pendingJobs.isEmpty {
                EmptyLibrary(model: model)
            } else {
                ContentUnavailableView {
                    Label(filter == .music ? "No Music Yet" : "No Videos Yet", systemImage: filter.symbol)
                } description: {
                    Text(filter == .music ? "Choose Audio when you download to save songs here."
                                          : "Videos you download appear here.")
                }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 36) {
                    if search.isEmpty && filter == .all {
                        if let latest = items.first {
                            FeaturedCard(item: latest, model: model) { play(latest) }
                        }
                        QuickActions(model: model)
                    }
                    if !items.isEmpty {
                        HStack(spacing: 12) {
                            Text(search.isEmpty ? (filter == .all ? "Library" : filter.title) : "Results")
                                .font(.title2.weight(.bold))
                            Spacer()
                            Picker("Group By", selection: $model.libraryGrouping) {
                                ForEach(LibraryGrouping.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .help("Group by date added or by channel")
                        }
                        .padding(.bottom, -18)
                    }
                    if !pending.isEmpty {
                        section("Downloading", count: pending.count) {
                            ForEach(pending) { job in
                                PendingCard(job: job, model: model)
                                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                    }
                    ForEach(groups) { group in
                        section(group.title, count: group.items.count) {
                            ForEach(group.items) { item in
                                LibraryCard(item: item, isSelected: selection.contains(item.id)) {
                                    play(item)
                                } select: { additive in
                                    select(item, additive: additive)
                                }
                                .contextMenu { menu(for: item) }
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(.space) {
                quickLookURL = quickLookURL == nil ? files(of: selection).first : nil
                return .handled
            }
            .onKeyPress(.return) {
                if let id = selection.first, let item = model.history.item(id: id) { play(item) }
                return .handled
            }
            .onDeleteCommand { if !selection.isEmpty { pendingRemoval = selection } }
            .onExitCommand { selection = [] }
        }
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text("\(count)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                content()
            }
        }
    }

    private var subtitle: String {
        let count = items.count
        guard count > 0 else { return "" }
        let bytes = items.reduce(Int64(0)) { $0 + ($1.byteCount ?? 0) }
        return "\(count) item\(count == 1 ? "" : "s")" + (bytes > 0 ? " · \(ByteSize.string(Double(bytes)))" : "")
    }

    private var removalTitle: String {
        pendingRemoval.count == 1
            ? "Remove “\(model.history.item(id: pendingRemoval.first!)?.title ?? "this item")”?"
            : "Remove \(pendingRemoval.count) items?"
    }

    // MARK: Actions

    private func files(of ids: Set<HistoryItem.ID>) -> [URL] {
        ids.compactMap(model.history.item(id:)).flatMap(\.fileURLs)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func select(_ item: HistoryItem, additive: Bool) {
        gridFocused = true
        if additive {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        } else {
            selection = [item.id]
        }
    }

    private func play(_ item: HistoryItem) {
        let files = files(of: [item.id])
        guard let file = files.first else {
            let elsewhere = item.deviceName.map { $0 != AppModel.deviceName } ?? false
            model.alert = AppModel.AppAlert(
                title: elsewhere ? "Downloaded on Another Mac" : "File Not Found",
                message: elsewhere
                    ? "“\(item.title)” is on \(item.deviceName ?? "another Mac"). Choose Download Again to get it here."
                    : "“\(item.title)” has been moved or deleted. Choose Download Again to get it back.")
            return
        }
        model.markPlayed([file])
        if MediaPlayer.canPlay(file) { openWindow(value: file) } else { NSWorkspace.shared.open(file) }
    }

    @ViewBuilder
    private func menu(for item: HistoryItem) -> some View {
        let ids = selection.contains(item.id) ? selection : [item.id]
        let files = files(of: ids)
        Button("Play") { play(item) }
            .disabled(files.isEmpty)
        Button("Quick Look") { selection = ids; quickLookURL = files.first }
            .disabled(files.isEmpty)
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(files) }
            .disabled(files.isEmpty)
        Button("Open With Default App") {
            model.markPlayed(Array(files.prefix(10)))
            files.prefix(10).forEach { NSWorkspace.shared.open($0) }
        }
        .disabled(files.isEmpty)
        Divider()
        if item.isAudio {
            Button("Add to Apple Music") { model.addToMusic(item) }
                .disabled(files.isEmpty)
        }
        if !files.isEmpty {
            Menu("Convert To") {
                ForEach(ConvertPreset.allCases) { preset in
                    Button(preset.title) {
                        model.convert(files, preset: preset)
                        model.selection = .convert
                    }
                }
            }
        }
        if !item.isAudio && item.quality != .best {
            Button("Replace with Best Quality") { model.upgradeToBestQuality(item) }
        }
        Button("Download Again") { model.redownload(item) }
        Divider()
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.sourceURL, forType: .string)
        }
        if let url = URL(string: item.sourceURL) {
            Button("Open Original Page") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button(ids.count == 1 ? "Remove…" : "Remove \(ids.count) Items…", role: .destructive) {
            pendingRemoval = ids
        }
    }
}

// MARK: - Cards

/// One saved item: artwork first, then title and channel — like Apple TV and Music.
struct LibraryCard: View {
    let item: HistoryItem
    let isSelected: Bool
    let play: () -> Void
    let select: (_ additive: Bool) -> Void
    @State private var hovering = false

    private var available: Bool { item.fileURLs.contains { FileManager.default.fileExists(atPath: $0.path) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Thumbnail(url: item.thumbnailURL, isAudio: item.isAudio, cornerRadius: 12)
                .overlay {
                    if hovering && available {
                        Button(action: play) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1.5)
                                .frame(width: 50, height: 50)
                                .background(.ultraThinMaterial.opacity(0.9), in: Circle())
                                .environment(\.colorScheme, .dark)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .accessibilityLabel("Play")
                    }
                }
                .overlay(alignment: .bottomTrailing) { badges }
                .overlay(alignment: .bottomLeading) {
                    if let duration = item.duration, duration > 0, !item.isPlaylist {
                        Text(Timecode.string(duration))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(8)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: isSelected ? 3 : 0)
                }
                .shadow(color: .black.opacity(hovering ? 0.22 : 0.10), radius: hovering ? 16 : 6, y: hovering ? 8 : 3)
                .scaleEffect(hovering ? 1.015 : 1)
                .opacity(available ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(available ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: play)
        .simultaneousGesture(TapGesture().modifiers(.command).onEnded { select(true) })
        .simultaneousGesture(TapGesture().onEnded { select(false) })
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.18), value: hovering)
        .animation(.smooth(duration: 0.15), value: isSelected)
        .help(item.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Play", play)
    }

    private var caption: String {
        if !available {
            if let device = item.deviceName, device != AppModel.deviceName { return "On \(device)" }
            return "Moved or deleted"
        }
        var parts: [String] = []
        if let uploader = item.uploader { parts.append(uploader) }
        if item.isPlaylist { parts.append("\(item.filePaths.count) items") }
        return parts.isEmpty ? item.date.formatted(date: .abbreviated, time: .omitted) : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if item.isPlaylist { badge("square.stack.fill") }
            if item.isAudio { badge("music.note") }
        }
        .padding(8)
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.black.opacity(0.55), in: Circle())
    }
}

/// A download in progress, shown where it will land in the library.
struct PendingCard: View {
    let job: DownloadJob
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Thumbnail(url: job.info?.thumbnailURL, isAudio: job.options.isAudio, cornerRadius: 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(job.phase == .failed ? 0.5 : 0.38))
                }
                .overlay {
                    ProgressRing(job: job) { primaryAction() }
                }
                .shadow(color: .black.opacity(0.10), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Text(job.phase == .failed ? (job.errorMessage ?? "Download failed") : job.statusLine)
                    .font(.caption)
                    .foregroundStyle(job.phase == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .monospacedDigit()
            }
            .padding(.horizontal, 2)
        }
        .contextMenu {
            switch job.phase {
            case .preparing, .downloading, .processing, .queued:
                Button("Pause") { model.pause(job) }
                Button("Stop") { model.cancel(job) }
            case .paused:
                Button("Resume") { model.resume(job) }
            case .failed:
                Button("Try Again") { model.retry(job) }
                Button("Copy Error Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(job.url)\n\(job.technicalError ?? job.statusLine)", forType: .string)
                }
            default:
                EmptyView()
            }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(job.url, forType: .string)
            }
            Divider()
            Button("Remove", role: .destructive) { model.remove(job) }
        }
        .help(job.statusLine)
    }

    private func primaryAction() {
        switch job.phase {
        case .preparing, .downloading, .queued: model.pause(job)
        case .paused: model.resume(job)
        case .failed: model.retry(job)
        default: break
        }
    }
}

/// App Store–style ring over the artwork: tap to pause, resume or retry.
struct ProgressRing: View {
    let job: DownloadJob
    let action: () -> Void
    @State private var hovering = false
    @State private var spin = false

    private var symbol: String {
        switch job.phase {
        case .paused: return "play.fill"
        case .failed: return "arrow.clockwise"
        case .queued: return hovering ? "pause.fill" : "clock"
        case .processing: return "gearshape.fill"
        default: return hovering ? "pause.fill" : "stop.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 4)
                if job.phase == .failed {
                    Circle().stroke(Color.red.opacity(0.9), lineWidth: 4)
                } else if job.progressIsIndeterminate || job.phase == .queued || job.phase == .processing {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                        .onAppear { spin = true }
                } else {
                    Circle()
                        .trim(from: 0, to: max(0.02, job.progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.4), value: job.progress)
                }
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(job.phase == .paused ? "Resume" : job.phase == .failed ? "Try Again" : "Pause")
        .accessibilityLabel(job.phase == .paused ? "Resume" : job.phase == .failed ? "Try Again" : "Pause")
        .accessibilityValue(job.progressIsIndeterminate ? "" : "\(Int(job.progress * 100)) percent")
    }
}

// MARK: - Empty library


/// A first-run welcome under the link bar: what My Videos does, in one color.
private struct EmptyLibrary: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 14) {
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 54, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                Text("Save anything you watch or hear.")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.4)
                Text("Paste a link above, press ⌘V anywhere, or drop a link on this window.\nVideos, playlists and songs from YouTube, Vimeo, TikTok and more than a thousand other sites.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            QuickActions(model: model)
                .frame(maxWidth: 900)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}

// MARK: - Featured

/// The latest download, large, on a wash of its own artwork — like Apple TV's Up Next.
struct FeaturedCard: View {
    let item: HistoryItem
    let model: AppModel
    let play: () -> Void
    @State private var hovering = false

    private var files: [URL] { item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) } }

    var body: some View {
        HStack(spacing: 28) {
            Thumbnail(url: item.thumbnailURL, isAudio: item.isAudio, cornerRadius: 12)
                .frame(width: 320, height: 180)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                        .frame(width: 56, height: 56)
                        .background(.ultraThinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                        .opacity(hovering && !files.isEmpty ? 1 : 0)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                .onTapGesture { if !files.isEmpty { play() } }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.isAudio ? "LATEST SONG" : "LATEST DOWNLOAD")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.6))
                Text(item.title)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Button(action: play) {
                        Label("Play", systemImage: "play.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(height: 34)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(files.isEmpty)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(files)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                    .disabled(files.isEmpty)
                    if item.isAudio {
                        Button {
                            model.addToMusic(item)
                        } label: {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.16), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Add to Apple Music")
                        .disabled(files.isEmpty)
                    }
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color(white: 0.09)
                Artwork(url: item.thumbnailURL)
                    .blur(radius: 90)
                    .saturation(1.4)
                    .opacity(0.8)
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.6)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
        .contextMenu {
            Button("Play", action: play).disabled(files.isEmpty)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(files) }.disabled(files.isEmpty)
        }
    }

    private var details: String {
        var parts: [String] = []
        if let uploader = item.uploader { parts.append(uploader) }
        if let duration = item.duration, duration > 0, !item.isPlaylist { parts.append(Timecode.string(duration)) }
        if item.isPlaylist { parts.append("\(item.filePaths.count) items") }
        parts.append(item.date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: "  ·  ")
    }
}

/// Artwork that fills its frame (for washes and backdrops).
private struct Artwork: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if let url {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

// MARK: - Shortcuts

/// Quiet shortcuts to the other things My Videos does. One color, no fuss.
struct QuickActions: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ShortcutTile(title: "Follow a Channel", subtitle: "New uploads save themselves",
                         symbol: "person.crop.circle.badge.plus") {
                model.subscribeRequest = .init(link: "")
            }
            ShortcutTile(title: "Convert a File", subtitle: "MP3, smaller video or GIF",
                         symbol: "arrow.triangle.2.circlepath") {
                model.selection = .convert
            }
            ShortcutTile(title: "Use on iPhone", subtitle: "Send links and watch",
                         symbol: "iphone") {
                NSApp.activate()
                openSettings()
            }
        }
    }
}

private struct ShortcutTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .offset(x: hovering ? 2 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(hovering ? 0.075 : 0.045),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.18), value: hovering)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
