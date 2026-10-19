//
//  SettingsView.swift
//  My Videos
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Accounts", systemImage: "person.crop.circle") { AccountSettings() }
            Tab("Components", systemImage: "shippingbox") { ComponentSettings() }
        }
        .frame(width: 540)
        .scenePadding()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs

    var body: some View {
        Form {
            Section {
                LabeledContent("Save downloads to") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: prefs.destination.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(FileManager.default.displayName(atPath: prefs.destination.path))
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Toggle("Add audio downloads to Apple Music", isOn: $prefs.addToMusic)
                Toggle("Embed cover art and details", isOn: $prefs.embedArtwork)
            } header: {
                Text("Downloads")
            }

            Section {
                Toggle("Notify me when downloads finish", isOn: $prefs.notificationsEnabled)
                Toggle("Offer to download links I copy", isOn: $prefs.clipboardDetection)
                Toggle("Show My Videos in the menu bar", isOn: $prefs.showMenuBarExtra)
            } header: {
                Text("Convenience")
            } footer: {
                Text("You can also select a link in any app and choose Services → Download with My Videos, or use the Share menu.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = prefs.destination
        if panel.runModal() == .OK, let url = panel.url { prefs.destination = url }
    }
}

// MARK: - Accounts

private struct AccountSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs
    @Environment(\.openWindow) private var openWindow
    @State private var signedInSites: [String] = []
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section {
                Picker("Sign in using", selection: $prefs.cookieSource) {
                    ForEach(CookieSource.allCases) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text("Public videos never need a sign-in. Use one for private, members-only or age-restricted videos.")
                    .foregroundStyle(.secondary)
            }

            switch prefs.cookieSource {
            case .none:
                EmptyView()
            case .builtIn:
                Section {
                    if signedInSites.isEmpty {
                        LabeledContent("Signed in to", value: "No sites yet")
                    } else {
                        LabeledContent("Signed in to") {
                            Text(signedInSites.joined(separator: ", "))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Sign In to a Site…") { openWindow(id: "signin") }
                        Spacer()
                        Button("Sign Out of All Sites", role: .destructive) { confirmSignOut = true }
                            .disabled(signedInSites.isEmpty)
                    }
                } header: {
                    Text("My Videos Sign-In")
                } footer: {
                    Text("Sign in once in My Videos’ own browser window. Your sign-ins stay private on this Mac and are only shared with yt-dlp while downloading.")
                        .foregroundStyle(.secondary)
                }
            case .browser:
                Section {
                    Picker("Browser", selection: $prefs.cookieBrowser) {
                        ForEach(CookieBrowser.allCases) { Text($0.displayName).tag($0) }
                    }
                } footer: {
                    Text("Uses the sign-ins from a browser you already use. macOS may ask for permission, and Safari often blocks this — if it fails, use My Videos Sign-In instead.")
                        .foregroundStyle(.secondary)
                }
            case .file:
                Section {
                    LabeledContent("Cookies file") {
                        HStack {
                            Text(prefs.cookieFilePath.isEmpty ? "None" : (prefs.cookieFilePath as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseCookieFile)
                        }
                    }
                } footer: {
                    Text("A Netscape-format cookies.txt exported from a browser where you’re signed in.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: prefs.cookieSource) { await reloadSites() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await reloadSites() }
        }
        .confirmationDialog("Sign out of all sites?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await SignInSession.signOutEverywhere()
                    await reloadSites()
                }
            }
        } message: {
            Text("Private videos won’t download until you sign in again.")
        }
    }

    private func reloadSites() async {
        signedInSites = await SignInSession.signedInSites()
    }

    private func chooseCookieFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.text, .plainText, .item]
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { prefs.cookieFilePath = url.path }
    }
}

// MARK: - Components

private struct ComponentSettings: View {
    @Bindable private var prefs = AppModel.shared.prefs
    private var toolchain: Toolchain { AppModel.shared.toolchain }

    var body: some View {
        Form {
            Section {
                LabeledContent("yt-dlp") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(toolchain.ytdlpVersion ?? (toolchain.ytdlp == nil ? "Not installed" : "Unknown version"))
                            .monospacedDigit()
                        if toolchain.updateAvailable, let latest = toolchain.latestYtdlpVersion {
                            Text("Version \(latest) available")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        } else if toolchain.latestYtdlpVersion != nil {
                            Text("Up to date")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("ffmpeg", value: toolchain.ffmpegVersion ?? (toolchain.ffmpeg == nil ? "Not installed" : "Installed"))
                LabeledContent("Browser impersonation") {
                    Label(toolchain.impersonationAvailable ? "Available" : "Unavailable",
                          systemImage: toolchain.impersonationAvailable ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(toolchain.impersonationAvailable ? .green : .secondary)
                }
                .help("Lets downloads get past sites that block automated tools.")

                HStack {
                    if toolchain.operation != nil || toolchain.isCheckingForUpdates {
                        ProgressView().controlSize(.small)
                        Text(toolchain.operation == .installing ? "Installing…"
                             : toolchain.operation == .updating ? "Updating…" : "Checking…")
                            .foregroundStyle(.secondary)
                    } else if let error = toolchain.operationError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !toolchain.isReady && toolchain.brew != nil {
                        Button("Install Missing") { Task { await toolchain.installMissing(log: AppModel.shared.log) } }
                            .disabled(toolchain.operation != nil)
                    } else if toolchain.updateAvailable {
                        Button("Update yt-dlp") { Task { await toolchain.updateYtdlp(log: AppModel.shared.log) } }
                            .disabled(toolchain.operation != nil)
                    } else {
                        Button("Check for Updates") {
                            Task {
                                await toolchain.refresh()
                                await toolchain.checkForUpdates()
                            }
                        }
                        .disabled(toolchain.operation != nil || toolchain.isCheckingForUpdates)
                    }
                }
            } header: {
                Text("Download Tools")
            }

            Section {
                Toggle("Check for yt-dlp updates weekly", isOn: $prefs.autoCheckUpdates)
                if let last = Toolchain.lastUpdateCheck {
                    LabeledContent("Last checked", value: last.formatted(.relative(presentation: .named)))
                }
            } footer: {
                Text("Video sites change often. Keeping yt-dlp current is the best way to keep downloads working.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
