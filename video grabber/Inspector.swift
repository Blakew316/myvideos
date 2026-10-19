//
//  Inspector.swift
//  My Videos
//
//  The right-hand inspector: Info about what's selected in the library, or Activity
//  with yt-dlp and ffmpeg's output. One inspector, two panes, as in Xcode.
//

import SwiftUI
import AppKit

struct LibraryInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Pane", selection: $model.inspectorPane) {
                ForEach(InspectorPane.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            switch model.inspectorPane {
            case .info: InfoPane(model: model)
            case .activity: ActivityPane(log: model.activityLog)
            }
        }
    }
}

// MARK: - Info

private struct InfoPane: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var selected: [HistoryItem] {
        model.librarySelection.compactMap(model.history.item(id:)).sorted { $0.date > $1.date }
    }

    var body: some View {
        let items = selected
        if items.isEmpty {
            ContentUnavailableView("No Selection", systemImage: "info.circle",
                                   description: Text("Select something in your library to see its details."))
        } else if items.count == 1, let item = items.first {
            ItemInfo(item: item, model: model)
        } else {
            MultipleInfo(items: items, model: model)
        }
    }
}

private struct ItemInfo: View {
    let item: HistoryItem
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var files: [URL] { item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Thumbnail(url: item.thumbnailURL, isAudio: item.isAudio, cornerRadius: 10)
                    .overlay(alignment: .bottom) {
                        if let progress = item.watchProgress, !item.isWatched {
                            WatchProgressBar(progress: progress).padding(8)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let uploader = item.uploader {
                        Text(uploader).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        play()
                    } label: {
                        Label(item.watchProgress != nil && !item.isWatched ? "Resume" : "Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(files.isEmpty)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(files)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Show in Finder")
                    .disabled(files.isEmpty)
                }
                .controlSize(.large)

                Toggle("Watched", isOn: Binding(
                    get: { item.isWatched },
                    set: { model.markWatched([item.id], $0) }))

                Divider()

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                    row("Kind", item.isPlaylist ? "Playlist · \(item.filePaths.count) items" : item.isAudio ? "Audio" : "Video")
                    if let duration = item.duration, duration > 0 { row("Length", Timecode.string(duration)) }
                    if let progress = item.watchProgress, let duration = item.duration, !item.isWatched {
                        row("Stopped at", "\(Timecode.string(progress * duration)) (\(Int(progress * 100))%)")
                    }
                    if let bytes = item.byteCount { row("Size", ByteSize.string(Double(bytes))) }
                    if let quality = item.quality, !item.isAudio { row("Quality", quality.displayName) }
                    if let format = files.first?.pathExtension.uppercased(), !format.isEmpty { row("Format", format) }
                    row("Added", item.date.formatted(date: .abbreviated, time: .shortened))
                    if let played = item.lastPlayedAt { row("Last opened", played.formatted(.relative(presentation: .named))) }
                    if let device = item.deviceName { row("Downloaded on", device) }
                    let inCollections = model.collections.items.filter { !$0.isSmart && $0.itemIDs.contains(item.id) }
                    if !inCollections.isEmpty { row("Collections", inCollections.map(\.name).joined(separator: ", ")) }
                }
                .font(.callout)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Location").font(.callout.weight(.medium))
                    if let file = files.first {
                        Text(file.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(4)
                            .truncationMode(.middle)
                    } else {
                        Text("Moved or deleted").font(.caption).foregroundStyle(.orange)
                    }
                    Text("Source").font(.callout.weight(.medium)).padding(.top, 6)
                    if let url = URL(string: item.sourceURL) {
                        Link(item.sourceURL, destination: url)
                            .font(.caption)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }

                Divider()

                HStack {
                    Menu("Convert To") {
                        ForEach(ConvertPreset.allCases) { preset in
                            Button(preset.title) {
                                model.convert(files, preset: preset)
                                model.selection = .convert
                            }
                        }
                    }
                    .disabled(files.isEmpty)
                    .fixedSize()
                    Spacer()
                    Button("Download Again") { model.redownload(item) }
                }
                .controlSize(.small)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }

    private func play() {
        guard let file = files.first else { return }
        model.markPlayed([file])
        if MediaPlayer.canPlay(file) { openWindow(value: file) } else { NSWorkspace.shared.open(file) }
    }
}

private struct MultipleInfo: View {
    let items: [HistoryItem]
    let model: AppModel

    var body: some View {
        let bytes = items.reduce(Int64(0)) { $0 + ($1.byteCount ?? 0) }
        let seconds = items.reduce(0.0) { $0 + ($1.duration ?? 0) }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: -28) {
                ForEach(items.prefix(3).reversed()) { item in
                    Thumbnail(url: item.thumbnailURL, isAudio: item.isAudio, cornerRadius: 8)
                        .frame(width: 120)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            Text("\(items.count) Items").font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    Text("Total size").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(ByteSize.string(Double(bytes)))
                }
                if seconds > 0 {
                    GridRow {
                        Text("Total length").foregroundStyle(.secondary)
                        Text(Timecode.string(seconds))
                    }
                }
                GridRow {
                    Text("Watched").foregroundStyle(.secondary)
                    Text("\(items.filter(\.isWatched).count) of \(items.count)")
                }
            }
            .font(.callout)
            HStack {
                Button("Mark as Watched") { model.markWatched(Set(items.map(\.id)), true) }
                Button("Mark as Unwatched") { model.markWatched(Set(items.map(\.id)), false) }
            }
            .controlSize(.small)
            Spacer()
        }
        .padding(16)
    }
}

/// A thin bar showing how far into an item you got.
struct WatchProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.black.opacity(0.45))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: max(4, geo.size.width * progress))
                }
        }
        .frame(height: 4)
        .accessibilityLabel("\(Int(progress * 100)) percent watched")
    }
}

// MARK: - Activity

private struct ActivityPane: View {
    let log: String

    var body: some View {
        VStack(spacing: 0) {
            if log.isEmpty {
                ContentUnavailableView("No Activity Yet", systemImage: "text.alignleft",
                                       description: Text("Technical details from yt-dlp and ffmpeg appear here while they run."))
            } else {
                ScrollView {
                    Text(log)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .defaultScrollAnchor(.bottom)
                Divider()
                HStack {
                    Spacer()
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log, forType: .string)
                    }
                    .controlSize(.small)
                }
                .padding(10)
            }
        }
    }
}
