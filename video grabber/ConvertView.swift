//
//  ConvertView.swift
//  My Videos
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Drop in any video or song and turn it into something more useful. The format lives in
/// the toolbar; files wait in "Ready to Convert" until you start them.
struct ConvertView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false

    /// Video formats can't be made from a song.
    private var onlyAudioStaged: Bool {
        !model.stagedFiles.isEmpty && model.stagedFiles.allSatisfy { MediaPlayer.isAudio($0) }
    }

    var body: some View {
        Group {
            if model.stagedFiles.isEmpty && model.conversions.isEmpty {
                ContentUnavailableView {
                    Label("Convert Videos and Songs", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Drop files here, or choose them, to make an MP3, a smaller video or a GIF. Converted files are saved next to the originals.")
                } actions: {
                    Button("Choose Files…", action: chooseFiles)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.stage(files)
            return true
        } isTargeted: { isTargeted = $0 }
        .navigationTitle("Convert")
        .navigationSubtitle(model.convertPreset.subtitle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Convert To", selection: $model.convertPreset) {
                    ForEach(ConvertPreset.allCases) { preset in
                        Label(preset.title, systemImage: preset.symbol).tag(preset)
                            .disabled(onlyAudioStaged && preset.needsVideo)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Choose what to convert files into")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: chooseFiles) {
                    Label("Add Files", systemImage: "plus")
                }
                .help("Choose files to convert")
            }
        }
        .animation(.smooth(duration: 0.25), value: model.conversions.map(\.id))
        .animation(.smooth(duration: 0.25), value: model.stagedFiles)
        .animation(.smooth(duration: 0.2), value: isTargeted)
    }

    private var list: some View {
        List {
            if !model.stagedFiles.isEmpty {
                Section {
                    ForEach(model.stagedFiles, id: \.self) { file in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            Text(file.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.stagedFiles.removeAll { $0 == file }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tertiary)
                            .help("Remove")
                            .accessibilityLabel("Remove \(file.lastPathComponent)")
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Ready to Convert")
                } footer: {
                    HStack {
                        if onlyAudioStaged && model.convertPreset.needsVideo {
                            Label("Choose an audio format for songs.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button(convertTitle) {
                            model.convert(model.stagedFiles, preset: model.convertPreset)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(onlyAudioStaged && model.convertPreset.needsVideo)
                    }
                    .padding(.top, 6)
                }
            }

            if !model.conversions.isEmpty {
                Section {
                    ForEach(model.conversions.reversed()) { job in
                        ConversionRow(job: job) { model.removeConversion(job) }
                    }
                } header: {
                    HStack {
                        Text("Conversions")
                        Spacer()
                        Button("Clear Finished") { model.clearFinishedConversions() }
                            .buttonStyle(.link)
                            .font(.callout)
                            .disabled(!model.conversions.contains { $0.phase != .waiting && $0.phase != .converting })
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
    }

    private var convertTitle: String {
        let count = model.stagedFiles.count
        return count == 1 ? "Convert to \(model.convertPreset.shortName)"
                          : "Convert \(count) Files to \(model.convertPreset.shortName)"
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .audio, .video, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK else { return }
        model.stage(panel.urls)
    }
}

private struct ConversionRow: View {
    let job: ConvertJob
    let remove: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: (job.output ?? job.input).path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.output?.lastPathComponent ?? job.input.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if job.phase == .converting {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
                Text("\(job.preset.title) · \(job.message)")
                    .font(.caption)
                    .foregroundStyle(job.phase == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .monospacedDigit()
            }
            Spacer()
            HStack(spacing: 4) {
                if job.phase == .finished, let output = job.output {
                    if MediaPlayer.canPlay(output) {
                        iconButton("play.fill", help: "Play") { openWindow(value: output) }
                    }
                    iconButton("magnifyingglass.circle", help: "Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                } else if job.phase == .converting || job.phase == .waiting {
                    iconButton("xmark.circle", help: "Stop", action: remove)
                } else {
                    iconButton("xmark.circle", help: "Remove", action: remove)
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            if job.phase == .finished, let output = job.output {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
            }
            Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([job.input]) }
            Divider()
            Button(job.phase == .converting || job.phase == .waiting ? "Stop" : "Remove", action: remove)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
