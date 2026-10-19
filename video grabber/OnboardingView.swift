//
//  OnboardingView.swift
//  My Videos
//

import SwiftUI
import AppKit

/// First-launch welcome, then a one-click setup of the tools My Videos needs.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .welcome
    @State private var copied = false

    enum Step { case welcome, setup }

    private var toolchain: Toolchain { model.toolchain }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .setup: setup
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.push(from: .trailing))

            Divider()
            footer
        }
        .frame(width: 580, height: 660)
        .background(WindowBackdrop())
        .animation(.smooth(duration: 0.35), value: step)
        .onAppear {
            if model.prefs.hasCompletedOnboarding { step = .setup }
        }
        .interactiveDismissDisabled(!toolchain.isReady && !model.prefs.hasCompletedOnboarding)
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                AppGlyph(size: 88)
                Text("Welcome to My Videos")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.3)
            }
            .padding(.top, 36)

            VStack(alignment: .leading, spacing: 18) {
                feature("arrow.down.circle.fill", .blue, "Save From Almost Anywhere",
                        "Paste a link from YouTube, Vimeo and thousands of other sites — videos, songs or entire playlists.")
                feature("dot.radiowaves.left.and.right", .red, "Follow Your Favorite Channels",
                        "Subscribe, and new uploads download on their own.")
                feature("music.note", .pink, "Straight Into Apple Music",
                        "Songs arrive with title, artist, cover art and lyrics.")
                feature("wand.and.sparkles", .orange, "Trim, Skip and Convert",
                        "Keep just the part you want, skip sponsor segments, or convert any file.")
                feature("menubar.rectangle", .indigo, "Always Within Reach",
                        "Use the menu bar, the Share menu, Shortcuts or Siri.")
            }
            .padding(.horizontal, 56)
            Spacer()
        }
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(color.gradient)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: toolchain.isReady ? "checkmark.seal.fill" : "shippingbox.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(toolchain.isReady ? Color.green.gradient : Color.blue.gradient)
                    .contentTransition(.symbolEffect(.replace))
                Text(toolchain.isReady ? "You’re All Set" : "Install the Download Tools")
                    .font(.title.weight(.bold))
                Text(toolchain.isReady
                     ? "Everything My Videos needs is installed."
                     : "My Videos uses two free, open-source tools to download and convert video.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36)
            .padding(.horizontal, 48)

            FormCard {
                toolRow("yt-dlp", "Finds and downloads the video", toolchain.ytdlpVersion, installed: toolchain.ytdlp != nil)
                toolRow("ffmpeg", "Combines and converts the files", toolchain.ffmpegVersion, installed: toolchain.ffmpeg != nil)
            }
            .padding(.horizontal, 48)

            if !toolchain.isReady {
                if toolchain.brew != nil {
                    VStack(spacing: 10) {
                        if toolchain.operation == .installing {
                            ProgressView("Installing… this can take a few minutes.")
                                .controlSize(.small)
                        }
                        if let error = toolchain.operationError {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 48)
                } else {
                    homebrewHelp.padding(.horizontal, 48)
                }
            }
            Spacer()
        }
    }

    private func toolRow(_ name: String, _ purpose: String, _ version: String?, installed: Bool) -> some View {
        FormRow(title: name, systemImage: installed ? "checkmark" : "arrow.down",
                color: installed ? .green : .gray,
                detail: purpose) {
            Text(installed ? (version.map { "Version \($0)" } ?? "Installed") : "Not installed")
                .foregroundStyle(installed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .monospacedDigit()
        }
    }

    private static let brewCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    private var homebrewHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("First, install Homebrew")
                .font(.headline)
            Text("Homebrew installs developer tools safely. Paste this into Terminal, follow the prompts, then come back and click Check Again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.brewCommand, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy Command", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button("Open Terminal") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                Spacer()
                Button("Check Again") { Task { await toolchain.refresh() } }
            }
            .buttonStyle(.glass)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step == .setup && !toolchain.isReady {
                Button("Set Up Later") { finish() }
                    .buttonStyle(.glass)
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Continue") {
                    if toolchain.isReady { finish() } else { step = .setup }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            case .setup:
                if toolchain.isReady {
                    Button("Start Downloading") { finish() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                } else if toolchain.brew != nil {
                    Button("Install \(toolchain.missingTools.joined(separator: " & "))") {
                        Task { await toolchain.installMissing(log: model.log) }
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(toolchain.operation != nil)
                }
            }
        }
        .controlSize(.large)
        .padding(20)
    }

    private func finish() {
        model.prefs.hasCompletedOnboarding = true
        dismiss()
        model.focusRequest += 1
    }
}
