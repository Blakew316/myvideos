//
//  LibraryViews.swift
//  My Videos
//

import SwiftUI
import AppKit

// MARK: - Queue

struct QueueView: View {
    @Bindable var model: AppModel

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
                    ForEach(model.jobs) { job in
                        JobRow(job: job, model: model)
                            .listRowSeparator(.visible)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(WindowBackdrop())
        .navigationTitle("Queue")
        .navigationSubtitle(queueSubtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
    }

    private var queueSubtitle: String {
        let pending = model.pendingCount
        return pending == 0 ? "" : "\(pending) remaining"
    }
}

struct JobRow: View {
    let job: DownloadJob
    let model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Thumbnail(url: job.info?.thumbnailURL, isAudio: job.options.isAudio, cornerRadius: 6)
                .frame(width: 96)
                .overlay(alignment: .bottomTrailing) { musicBadge }

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
        .onTapGesture(count: 2) {
            if job.phase == .finished, let file = job.savedFiles.first { NSWorkspace.shared.open(file) }
        }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch job.musicState {
        case .adding: return job.statusLine + " · Adding to Apple Music…"
        case .added: return job.statusLine + " · Added to Apple Music"
        case .failed(let message): return job.statusLine + " · " + message
        case .none: return job.statusLine
        }
    }

    @ViewBuilder
    private var musicBadge: some View {
        if job.musicState == .added {
            IconTile(systemImage: "music.note", color: .pink, size: 18)
                .padding(4)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            switch job.phase {
            case .queued, .preparing, .downloading, .processing:
                circleButton("xmark", help: "Stop") { model.cancel(job) }
            case .failed, .cancelled:
                circleButton("arrow.clockwise", help: "Try Again") { model.retry(job) }
                circleButton("xmark", help: "Remove") { model.remove(job) }
            case .finished:
                if let file = job.savedFiles.first, job.savedFiles.count == 1 {
                    circleButton("play.fill", help: "Open") { NSWorkspace.shared.open(file) }
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
            if let file = job.savedFiles.first {
                Button("Open") { NSWorkspace.shared.open(file) }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(job.savedFiles) }
            Divider()
        }
        if job.isActive || job.phase == .queued {
            Button("Stop") { model.cancel(job) }
        }
        if job.phase == .failed || job.phase == .cancelled {
            Button("Try Again") { model.retry(job) }
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.url, forType: .string)
        }
        Divider()
        Button("Remove from List", role: .destructive) { model.remove(job) }
    }
}

// MARK: - History

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var selection = Set<HistoryItem.ID>()
    @State private var confirmClear = false

    private var items: [HistoryItem] {
        let all = model.history.items
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            ($0.uploader?.localizedCaseInsensitiveContains(search) ?? false)
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
                    open(ids)
                }
                .onDeleteCommand { model.history.remove(ids: selection) }
            }
        }
        .background(WindowBackdrop())
        .navigationTitle("History")
        .searchable(text: $search, placement: .toolbar, prompt: "Search Downloads")
        .toolbar {
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

    private func open(_ ids: Set<HistoryItem.ID>) {
        let files = existingFiles(ids)
        if files.isEmpty, let item = ids.first.flatMap(model.history.item(id:)) {
            model.alert = AppModel.AppAlert(title: "File Not Found",
                                            message: "“\(item.title)” has been moved or deleted. You can download it again from the context menu.")
        }
        files.prefix(10).forEach { NSWorkspace.shared.open($0) }
    }

    @ViewBuilder
    private func menu(for ids: Set<HistoryItem.ID>) -> some View {
        let items = ids.compactMap(model.history.item(id:))
        if !items.isEmpty {
            Button("Open") { open(ids) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(existingFiles(ids)) }
                .disabled(existingFiles(ids).isEmpty)
            if items.count == 1, let item = items.first {
                if item.isAudio {
                    Button("Add to Apple Music") { model.addToMusic(item) }
                }
                Divider()
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
                if !fileExists {
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
