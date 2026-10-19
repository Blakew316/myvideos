//
//  LibraryViews.swift
//  My Videos
//

import SwiftUI
import AppKit

/// A download in the Downloads popover: artwork, progress and the controls that fit its state.
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
