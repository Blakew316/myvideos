//
//  MenuBarView.swift
//  My Videos
//

import SwiftUI
import AppKit

/// The menu bar extra: download a link without opening the main window.
struct MenuBarView: View {
    @Bindable private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppGlyph(size: 26)
                Text("My Videos").font(.headline)
                Spacer()
                if model.pendingCount > 0 {
                    Text("\(model.pendingCount) in queue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                TextField("Paste a link", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(download)
                Button("Download", action: download)
                    .buttonStyle(.glassProminent)
                    .disabled(URL(string: link.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") != true)
            }

            HStack(spacing: 8) {
                PasteButton(payloadType: String.self) { strings in
                    if let text = strings.first { model.downloadImmediately(text) }
                }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                Text("Paste a copied link to download it right away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !model.activeJobs.isEmpty {
                VStack(spacing: 8) {
                    ForEach(model.activeJobs.prefix(3)) { job in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(job.displayTitle)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    model.pause(job)
                                } label: {
                                    Image(systemName: "pause.fill")
                                }
                                .buttonStyle(.borderless)
                                .help("Pause")
                            }
                            JobProgressBar(job: job)
                            Text(job.statusLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                        .padding(10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
                    }
                }
            } else if let last = model.history.items.first {
                Button {
                    if let file = last.primaryFile { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                } label: {
                    HStack(spacing: 10) {
                        Thumbnail(url: last.thumbnailURL, isAudio: last.isAudio, cornerRadius: 4)
                            .frame(width: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last download").font(.caption).foregroundStyle(.secondary)
                            Text(last.title).font(.callout).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }

            Divider()

            if !model.subscriptions.items.isEmpty {
                Button {
                    Task { await model.checkAllSubscriptions(onlyDue: false) }
                } label: {
                    Label(model.checkingSubscriptions.isEmpty ? "Check Subscriptions Now" : "Checking Subscriptions…",
                          systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!model.checkingSubscriptions.isEmpty)
            }

            HStack {
                Button("Open My Videos") { showMainWindow(.home) }
                Spacer()
                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit My Videos")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func download() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.downloadImmediately(trimmed)
        link = ""
    }

    private func showMainWindow(_ page: SidebarItem) {
        model.selection = page
        openWindow(id: "main")
        NSApp.activate()
    }
}
