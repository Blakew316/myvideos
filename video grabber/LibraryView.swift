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
    @State private var sortOrder = [KeyPathComparator(\HistoryItem.date, order: .reverse)]
    @FocusState private var gridFocused: Bool
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 20, alignment: .top)]

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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker("View", selection: $model.libraryLayout) {
                        ForEach(LibraryLayout.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .help("Show items as icons or in a list")
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Group By", selection: $model.libraryGrouping) {
                            ForEach(LibraryGrouping.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
                    }
                    .menuIndicator(.hidden)
                    .disabled(model.libraryLayout == .list)
                    .help("Group by date added or by channel")
                }
            }
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
                if !model.pasteFromClipboard() { model.showNewDownload = true }
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
                ContentUnavailableView {
                    Label("No Downloads Yet", systemImage: "play.rectangle.on.rectangle")
                } description: {
                    Text("Paste a link, press ⌘V, or drop a link on this window to save a video, playlist or song.")
                } actions: {
                    Button("New Download…") { model.showNewDownload = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                ContentUnavailableView {
                    Label(filter == .music ? "No Music Yet" : "No Videos Yet", systemImage: filter.symbol)
                } description: {
                    Text(filter == .music ? "Choose Audio when you download to save songs here."
                                          : "Videos you download appear here.")
                }
            }
        } else if model.libraryLayout == .list {
            listContent
        } else {
            gridContent
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if !pending.isEmpty {
                    section("Downloading", count: pending.count) {
                        ForEach(pending) { job in
                            PendingCard(job: job, model: model)
                                .transition(.opacity)
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
                            .contextMenu { menu(for: selection.contains(item.id) ? selection : [item.id], primary: item) }
                            .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
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

    /// Finder-style list: sortable columns, multiple selection, double-click to play.
    private var listContent: some View {
        VStack(spacing: 0) {
            if !pending.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(pending) { job in
                            JobRow(job: job, model: model).padding(.horizontal, 16)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(pending.count) * 84, 220))
                Divider()
            }
            Table(items.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title) { item in
                    HStack(spacing: 10) {
                        Thumbnail(url: item.thumbnailURL, isAudio: item.isAudio, cornerRadius: 3)
                            .frame(width: 48, height: 27)
                        Text(item.title).lineLimit(1)
                    }
                    .opacity(item.isAvailable ? 1 : 0.5)
                }
                .width(min: 220, ideal: 380)
                TableColumn("Channel", value: \.channelSortKey) { item in
                    Text(item.uploader ?? "").foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 160)
                TableColumn("Kind", value: \.kindSortKey) { item in
                    Text(item.kindSortKey).foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 70)
                TableColumn("Duration", value: \.durationSortKey) { item in
                    Text(item.duration.map { Timecode.string($0) } ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 70)
                .alignment(.trailing)
                TableColumn("Size", value: \.sizeSortKey) { item in
                    Text(item.byteCount.map { ByteSize.string(Double($0)) } ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 80)
                .alignment(.trailing)
                TableColumn("Date Added", value: \.date) { item in
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .width(min: 110, ideal: 150)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: HistoryItem.ID.self) { ids in
                if let first = ids.first, let item = model.history.item(id: first) {
                    menu(for: ids, primary: item)
                }
            } primaryAction: { ids in
                if let first = ids.first, let item = model.history.item(id: first) { play(item) }
            }
            .onKeyPress(.space) {
                quickLookURL = quickLookURL == nil ? files(of: selection).first : nil
                return .handled
            }
            .onDeleteCommand { if !selection.isEmpty { pendingRemoval = selection } }
        }
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text("\(count)")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
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
    private func menu(for ids: Set<HistoryItem.ID>, primary item: HistoryItem) -> some View {
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
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                                .frame(width: 40, height: 40)
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
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                        .padding(-4)
                }
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .opacity(available ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.medium))
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
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)

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

// MARK: - Sorting

extension HistoryItem {
    var isAvailable: Bool { fileURLs.contains { FileManager.default.fileExists(atPath: $0.path) } }
    var channelSortKey: String { uploader ?? "" }
    var kindSortKey: String { isPlaylist ? "Playlist" : isAudio ? "Audio" : "Video" }
    var durationSortKey: Double { duration ?? 0 }
    var sizeSortKey: Int64 { byteCount ?? 0 }
}
