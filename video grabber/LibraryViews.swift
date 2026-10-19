//
//  LibraryViews.swift
//  My Videos
//

import SwiftUI
import AppKit
import QuickLook

// MARK: - Queue

struct QueueView: View {
    @Bindable var model: AppModel

    private var inProgress: [DownloadJob] { model.jobs.filter(\.isActive) }
    private var finished: [DownloadJob] { model.jobs.filter(\.isDone).reversed() }

    var body: some View {
        Group {
            if model.jobs.isEmpty {
                ContentUnavailableView {
                    Label("Nothing in the Queue", systemImage: "arrow.down.circle")
                } description: {
                    Text("Downloads you start appear here.")
                } actions: {
                    Button("New Download") { model.selection = .download; model.focusRequest += 1 }
                        .buttonStyle(.glassProminent)
                }
            } else {
                List {
                    if !inProgress.isEmpty {
                        Section("Downloading") {
                            ForEach(inProgress) { JobRow(job: $0, model: model) }
                        }
                    }
                    if !model.upNext.isEmpty {
                        Section {
                            ForEach(model.upNext) { JobRow(job: $0, model: model) }
                                .onMove { model.moveUpNext(from: $0, to: $1) }
                        } header: {
                            Text("Up Next")
                        } footer: {
                            if model.upNext.count > 1 {
                                Text("Drag to change the order.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if !finished.isEmpty {
                        Section("Finished") {
                            ForEach(finished) { JobRow(job: $0, model: model) }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(WindowBackdrop())
        .navigationTitle("Queue")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.pausedCount > 0 && model.pendingCount == 0 {
                    Button {
                        model.resumeAll()
                    } label: {
                        Label("Resume All", systemImage: "play.fill")
                    }
                    .help("Resume all paused downloads")
                } else {
                    Button {
                        model.pauseAll()
                    } label: {
                        Label("Pause All", systemImage: "pause.fill")
                    }
                    .help("Pause all downloads")
                    .disabled(model.pendingCount == 0)
                }
                Button {
                    model.clearFinished()
                } label: {
                    Label("Clear Finished", systemImage: "checkmark.circle.badge.xmark")
                }
                .help("Remove finished, failed and cancelled downloads from the list")
                .disabled(!model.jobs.contains { $0.isDone })
            }
        }
        .animation(.smooth(duration: 0.3), value: model.jobs.map(\.id))
        .animation(.smooth(duration: 0.3), value: model.jobs.map(\.phase))
    }

    private var subtitle: String {
        var parts: [String] = []
        if model.pendingCount > 0 { parts.append("\(model.pendingCount) remaining") }
        if model.pausedCount > 0 { parts.append("\(model.pausedCount) paused") }
        return parts.joined(separator: ", ")
    }
}

struct JobRow: View {
    let job: DownloadJob
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 14) {
            Thumbnail(url: job.info?.thumbnailURL, isAudio: job.options.isAudio, cornerRadius: 6)
                .frame(width: 96)
                .overlay(alignment: .bottomTrailing) { musicBadge }
                .opacity(job.phase == .paused ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(job.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if job.isActive {
                    JobProgressBar(job: job)
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(job.phase == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openFile() }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        var text = job.statusLine
        switch job.musicState {
        case .evening: text += " · Evening out volume…"
        case .findingLyrics: text += " · Finding lyrics…"
        case .adding: text += " · Adding to Apple Music…"
        case .added: text += " · Added to Apple Music"
        case .failed(let message): text += " · " + message
        case .none: break
        }
        if job.lyricsCount > 0, job.musicState != .findingLyrics {
            text += job.lyricsCount == 1 ? " · Lyrics added" : " · Lyrics added to \(job.lyricsCount) songs"
        }
        return text
    }

    @ViewBuilder
    private var musicBadge: some View {
        if job.musicState == .added {
            IconTile(systemImage: "music.note", color: .pink, size: 18)
                .padding(4)
        } else if job.phase == .paused {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white, .black.opacity(0.5))
                .padding(4)
        }
    }

    private func openFile() {
        guard job.phase == .finished, let file = job.savedFiles.first else { return }
        model.markPlayed([file])
        if MediaPlayer.canPlay(file) { openWindow(value: file) } else { NSWorkspace.shared.open(file) }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            switch job.phase {
            case .preparing, .downloading, .processing:
                circleButton("pause.fill", help: "Pause") { model.pause(job) }
                circleButton("xmark", help: "Stop") { model.cancel(job) }
            case .queued:
                circleButton("pause.fill", help: "Pause") { model.pause(job) }
                circleButton("xmark", help: "Remove") { model.remove(job) }
            case .paused:
                circleButton("play.fill", help: "Resume") { model.resume(job) }
                circleButton("xmark", help: "Remove") { model.remove(job) }
            case .failed, .cancelled:
                circleButton("arrow.clockwise", help: "Try Again") { model.retry(job) }
                circleButton("xmark", help: "Remove") { model.remove(job) }
            case .finished:
                if job.savedFiles.count == 1 {
                    circleButton("play.fill", help: "Play", action: openFile)
                }
                circleButton("magnifyingglass", help: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(job.savedFiles)
                }
            }
        }
    }

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private var menu: some View {
        if job.phase == .finished {
            if job.savedFiles.first != nil {
                Button("Play", action: openFile)
                Button("Open With Default App") { job.savedFiles.first.map { _ = NSWorkspace.shared.open($0) } }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(job.savedFiles) }
            Divider()
        }
        if job.isActive || job.phase == .queued {
            Button("Pause") { model.pause(job) }
            Button("Stop") { model.cancel(job) }
        }
        if job.phase == .paused {
            Button("Resume") { model.resume(job) }
        }
        if job.phase == .failed || job.phase == .cancelled {
            Button("Try Again") { model.retry(job) }
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.url, forType: .string)
        }
        if job.phase == .failed {
            Button("Copy Error Details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(job.url)\n\(job.technicalError ?? job.statusLine)", forType: .string)
            }
        }
        Divider()
        Button("Remove from List", role: .destructive) { model.remove(job) }
    }
}

// MARK: - History

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var selection = Set<HistoryItem.ID>()
    @State private var confirmClear = false
    @State private var quickLookURL: URL?
    @State private var showStorage = false
    @Environment(\.openWindow) private var openWindow

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", videos = "Videos", music = "Music"
        var id: String { rawValue }
    }

    private var items: [HistoryItem] {
        model.history.items.filter { item in
            switch filter {
            case .all: break
            case .videos: if item.isAudio { return false }
            case .music: if !item.isAudio { return false }
            }
            guard !search.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(search)
                || (item.uploader?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        Group {
            if model.history.items.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Everything you download is listed here, so it’s always easy to find again.")
                }
            } else if items.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(selection: $selection) {
                    ForEach(groupedItems, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.items) { item in
                                HistoryRow(item: item).tag(item.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: HistoryItem.ID.self) { ids in
                    menu(for: ids)
                } primaryAction: { ids in
                    play(ids)
                }
                .onDeleteCommand { model.history.remove(ids: selection) }
                .onKeyPress(.space) {
                    toggleQuickLook()
                    return .handled
                }
                .quickLookPreview($quickLookURL, in: existingFiles(selection))
            }
        }
        .background(WindowBackdrop())
        .navigationTitle("History")
        .searchable(text: $search, placement: .toolbar, prompt: "Search Downloads")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showStorage = true
                } label: {
                    Label("Storage", systemImage: "internaldrive")
                }
                .help("See how much space your downloads use")
                .disabled(model.history.items.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    confirmClear = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .help("Clear History")
                .disabled(model.history.items.isEmpty)
            }
        }
        .sheet(isPresented: $showStorage) { StorageView(model: model) }
        .onChange(of: quickLookURL) { if let url = quickLookURL { model.markPlayed([url]) } }
        .confirmationDialog("Clear your download history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.history.clear() }
        } message: {
            Text("Downloaded files stay where they are. Only the list is cleared.")
        }
    }

    private struct DayGroup {
        let title: String
        let items: [HistoryItem]
    }

    /// Today / Yesterday / This Week / Earlier, like Safari's History.
    private var groupedItems: [DayGroup] {
        let calendar = Calendar.current
        let now = Date()
        func bucket(_ date: Date) -> String {
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 { return "This Week" }
            return "Earlier"
        }
        var order: [String] = []
        var groups: [String: [HistoryItem]] = [:]
        for item in items {
            let key = bucket(item.date)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.map { DayGroup(title: $0, items: groups[$0] ?? []) }
    }

    private func existingFiles(_ ids: Set<HistoryItem.ID>) -> [URL] {
        ids.compactMap(model.history.item(id:)).flatMap(\.fileURLs)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func toggleQuickLook() {
        if quickLookURL != nil {
            quickLookURL = nil
        } else {
            quickLookURL = existingFiles(selection).first
        }
    }

    /// Double-click: play in the built-in player when possible, otherwise open normally.
    private func play(_ ids: Set<HistoryItem.ID>) {
        let files = existingFiles(ids)
        if files.isEmpty, let item = ids.first.flatMap(model.history.item(id:)) {
            let elsewhere = item.deviceName.map { $0 != AppModel.deviceName } ?? false
            model.alert = AppModel.AppAlert(
                title: elsewhere ? "Downloaded on Another Mac" : "File Not Found",
                message: elsewhere
                    ? "“\(item.title)” was downloaded on \(item.deviceName ?? "another Mac"). You can download it again here from the context menu."
                    : "“\(item.title)” has been moved or deleted. You can download it again from the context menu.")
            return
        }
        model.markPlayed(Array(files.prefix(5)))
        for file in files.prefix(5) {
            if MediaPlayer.canPlay(file) { openWindow(value: file) } else { NSWorkspace.shared.open(file) }
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<HistoryItem.ID>) -> some View {
        let items = ids.compactMap(model.history.item(id:))
        let files = existingFiles(ids)
        if !items.isEmpty {
            Button("Play") { play(ids) }
                .disabled(files.isEmpty)
            Button("Quick Look") { quickLookURL = files.first }
                .disabled(files.isEmpty)
            Button("Open With Default App") {
                model.markPlayed(Array(files.prefix(10)))
                files.prefix(10).forEach { NSWorkspace.shared.open($0) }
            }
            .disabled(files.isEmpty)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(files) }
                .disabled(files.isEmpty)
            if items.count == 1, let item = items.first {
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
                Divider()
                if !item.isAudio && item.quality != .best {
                    Button("Replace with Best Quality") { model.upgradeToBestQuality(item) }
                }
                Button("Download Again") { model.redownload(item) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.sourceURL, forType: .string)
                }
                if let url = URL(string: item.sourceURL) {
                    Button("Open Original Page") { NSWorkspace.shared.open(url) }
                }
            }
            Divider()
            Button(items.count == 1 ? "Remove from History" : "Remove \(items.count) Items from History",
                   role: .destructive) {
                model.history.remove(ids: ids)
            }
        }
    }
}

struct HistoryRow: View {
    let item: HistoryItem

    private var fileExists: Bool {
        item.fileURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var onAnotherMac: Bool {
        guard let device = item.deviceName else { return false }
        return device != AppModel.deviceName && !fileExists
    }

    var body: some View {
        HStack(spacing: 14) {
            Thumbnail(url: item.thumbnailURL, isAudio: item.isAudio, cornerRadius: 6)
                .frame(width: 96)
                .opacity(fileExists ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let cleaned = item.cleanedUpAt {
                    Label("Moved to Trash after watching · \(cleaned.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if onAnotherMac {
                    Label("On \(item.deviceName ?? "another Mac")", systemImage: "laptopcomputer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !fileExists {
                    Label("Moved or deleted", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: item.isAudio ? "music.note" : (item.isPlaylist ? "list.and.film" : "film"))
                .foregroundStyle(.tertiary)
                .help(item.isAudio ? "Audio" : (item.isPlaylist ? "Playlist" : "Video"))
        }
        .padding(.vertical, 5)
    }

    private var details: String {
        var parts: [String] = []
        if let uploader = item.uploader { parts.append(uploader) }
        if item.isPlaylist { parts.append("\(item.filePaths.count) files") }
        else if let duration = item.duration { parts.append(Timecode.string(duration)) }
        if let bytes = item.byteCount, bytes > 0 { parts.append(ByteSize.string(Double(bytes))) }
        parts.append(Calendar.current.isDateInToday(item.date)
                     ? item.date.formatted(date: .omitted, time: .shortened)
                     : item.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}
