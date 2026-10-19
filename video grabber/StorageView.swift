//
//  StorageView.swift
//  My Videos
//

import SwiftUI
import AppKit

/// How much space downloads use, and an easy way to clear out ones you no longer open.
struct StorageView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var summary: StorageSummary?
    @State private var unusedDays = 90
    @State private var selected = Set<UUID>()
    @State private var confirmTrash = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "internaldrive.fill", color: .gray, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Storage").font(.title2.weight(.bold))
                            Text("Space used by files you downloaded with My Videos.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let summary {
                        usageBar(summary)
                        unusedSection(summary)
                        largestSection(summary)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Measuring…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                if !selected.isEmpty, let summary {
                    let bytes = summary.entries.filter { selected.contains($0.id) }.reduce(Int64(0)) { $0 + $1.bytes }
                    Button("Move \(selected.count) to Trash (\(ByteSize.string(Double(bytes))))", role: .destructive) {
                        confirmTrash = true
                    }
                    .buttonStyle(.glass)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 600, height: 640)
        .background(WindowBackdrop())
        .task { await measure() }
        .confirmationDialog("Move \(selected.count) download\(selected.count == 1 ? "" : "s") to the Trash?",
                            isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive, action: trashSelected)
        } message: {
            Text("You can get them back from the Trash until it’s emptied.")
        }
    }

    // MARK: Sections

    private func usageBar(_ summary: StorageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ByteSize.string(Double(summary.totalBytes)))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                Text("used").foregroundStyle(.secondary)
                Spacer()
                if summary.freeBytes > 0 {
                    Text("\(ByteSize.string(Double(summary.freeBytes))) available on disk")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                let total = max(Double(summary.totalBytes + summary.freeBytes), 1)
                HStack(spacing: 2) {
                    Rectangle().fill(Color.blue.gradient)
                        .frame(width: geo.size.width * Double(summary.videoBytes) / total)
                    Rectangle().fill(Color.pink.gradient)
                        .frame(width: geo.size.width * Double(summary.musicBytes) / total)
                    Rectangle().fill(Color.primary.opacity(0.08))
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack(spacing: 18) {
                legend(.blue, "Videos", summary.videoBytes)
                legend(.pink, "Music", summary.musicBytes)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func legend(_ color: Color, _ title: String, _ bytes: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
            Text(ByteSize.string(Double(bytes))).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
    }

    private func unusedSection(_ summary: StorageSummary) -> some View {
        let unused = summary.untouched(days: unusedDays)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Not Opened Recently").font(.headline)
                Spacer()
                Picker("Not opened in", selection: $unusedDays) {
                    Text("1 Month").tag(30)
                    Text("3 Months").tag(90)
                    Text("6 Months").tag(180)
                    Text("1 Year").tag(365)
                }
                .labelsHidden()
                .fixedSize()
            }
            if unused.isEmpty {
                Text("Everything here has been opened recently.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                FormCard {
                    ForEach(unused.prefix(30)) { entry in row(entry) }
                }
                if unused.count > 1 {
                    Button("Select All \(unused.count)") { selected.formUnion(unused.map(\.id)) }
                        .buttonStyle(.link)
                }
            }
        }
    }

    private func largestSection(_ summary: StorageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Largest Downloads").font(.headline)
            FormCard {
                ForEach(summary.largest) { entry in row(entry) }
            }
        }
    }

    private func row(_ entry: StorageSummary.Entry) -> some View {
        HStack(spacing: 12) {
            Toggle(entry.title, isOn: Binding(
                get: { selected.contains(entry.id) },
                set: { if $0 { selected.insert(entry.id) } else { selected.remove(entry.id) } }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(systemName: entry.isAudio ? "music.note" : "film")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).lineLimit(1)
                Text(entry.lastOpened.map { "Opened \($0.formatted(.relative(presentation: .named)))" } ?? "Never opened")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteSize.string(Double(entry.bytes)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(entry.files)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Actions

    private func measure() async {
        let items = model.history.items
        let destination = model.prefs.destination
        summary = await Task.detached { StorageSummary.measure(items, destination: destination) }.value
    }

    private func trashSelected() {
        guard let summary else { return }
        for entry in summary.entries where selected.contains(entry.id) {
            for file in entry.files { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
        }
        selected.removeAll()
        Task { await measure() }
    }
}
