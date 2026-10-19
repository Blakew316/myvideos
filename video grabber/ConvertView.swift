//
//  ConvertView.swift
//  My Videos
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Drop in any video or song and turn it into something more useful.
struct ConvertView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Convert To")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ConvertPreset.allCases) { preset in
                            PresetCard(preset: preset, isSelected: model.convertPreset == preset) {
                                model.convertPreset = preset
                            }
                        }
                    }
                }

                dropZone

                if !model.conversions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Conversions")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear Finished") { model.clearFinishedConversions() }
                                .buttonStyle(.link)
                                .disabled(!model.conversions.contains { $0.phase != .waiting && $0.phase != .converting })
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(model.conversions.reversed().enumerated()), id: \.element.id) { index, job in
                                if index > 0 { Divider().padding(.leading, 56) }
                                ConversionRow(job: job) { model.removeConversion(job) }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(WindowBackdrop())
        .navigationTitle("Convert")
        .animation(.smooth(duration: 0.3), value: model.conversions.map(\.id))
        .animation(.smooth(duration: 0.3), value: model.stagedFiles)
    }

    // MARK: Drop zone

    private var dropZone: some View {
        VStack(spacing: 14) {
            if model.stagedFiles.isEmpty {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: isTargeted)
                VStack(spacing: 4) {
                    Text("Drop Videos or Songs Here")
                        .font(.title3.weight(.semibold))
                    Text("They’ll be converted to \(model.convertPreset.title) and saved next to the original.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Choose Files…", action: chooseFiles)
                    .buttonStyle(.glass)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.stagedFiles.count == 1 ? "Ready to Convert" : "\(model.stagedFiles.count) Files Ready")
                        .font(.title3.weight(.semibold))
                    ForEach(model.stagedFiles, id: \.self) { file in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button {
                                model.stagedFiles.removeAll { $0 == file }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(file.lastPathComponent)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Add More…", action: chooseFiles).buttonStyle(.glass)
                    Spacer()
                    Button("Convert to \(model.convertPreset.title)") {
                        model.convert(model.stagedFiles, preset: model.convertPreset)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [7, 5]))
        )
        .animation(.smooth(duration: 0.2), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.convert(files, preset: model.convertPreset)
            return true
        } isTargeted: { isTargeted = $0 }
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

private struct PresetCard: View {
    let preset: ConvertPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(systemImage: preset.symbol, color: color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title).font(.callout.weight(.semibold))
                    Text(preset.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.07), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var color: Color {
        switch preset {
        case .aac: return .pink
        case .mp3: return .red
        case .wav: return .orange
        case .compatible: return .blue
        case .smaller: return .teal
        case .gif: return .purple
        }
    }
}

private struct ConversionRow: View {
    let job: ConvertJob
    let remove: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: (job.output ?? job.input).path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.input.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if job.phase == .converting {
                    ProgressView(value: job.progress).controlSize(.small)
                }
                Text("\(job.preset.title) · \(job.message)")
                    .font(.caption)
                    .foregroundStyle(job.phase == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .monospacedDigit()
            }
            Spacer()
            HStack(spacing: 6) {
                if job.phase == .finished, let output = job.output {
                    if MediaPlayer.canPlay(output) {
                        roundButton("play.fill", help: "Play") { openWindow(value: output) }
                    }
                    roundButton("magnifyingglass", help: "Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                } else if job.phase == .converting || job.phase == .waiting {
                    roundButton("xmark", help: "Stop", action: remove)
                } else {
                    roundButton("xmark", help: "Remove", action: remove)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
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
}
