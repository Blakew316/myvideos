//
//  ContentView.swift
//  My Videos
//

import SwiftUI
import AppKit
import Combine

/// The main window: Library and Channels in the sidebar, the Downloads button in the
/// toolbar, and an optional Activity inspector for technical details.
struct ContentView: View {
    @Bindable private var model = AppModel.shared

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        DownloadsToolbarButton(model: model)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.showNewDownload = true
                        } label: {
                            Label("New Download", systemImage: "plus")
                        }
                        .help("New Download (⌘N)")
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 620)
        .inspector(isPresented: $model.showActivity) {
            ActivityInspector(log: model.activityLog)
                .inspectorColumnWidth(min: 280, ideal: 360, max: 600)
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(model: model)
        }
        .sheet(isPresented: $model.showStorage) { StorageView(model: model) }
        .sheet(isPresented: $model.showNewDownload) { NewDownloadSheet(model: model) }
        .sheet(item: $model.subscribeRequest) { request in
            SubscribeSheet(model: model, link: request.link)
        }
        .alert(item: $model.alert) { alert in
            if alert.showsAutomationButton {
                Alert(title: Text(alert.title), message: Text(alert.message),
                      primaryButton: .default(Text("Open Settings"), action: SystemSettings.openAutomation),
                      secondaryButton: .cancel(Text("Not Now")))
            } else {
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkClipboard()
            if model.prefs.iCloudSync { Task { await model.sync.sync(model: model) } }
        }
        .onAppear { model.checkClipboard() }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .home {
        case .library(let filter):
            LibraryView(model: model, filter: filter)
                .id(filter)
                .safeAreaInset(edge: .top, spacing: 0) { NoticeStrip(model: model) }
        case .subscriptions:
            SubscriptionsOverview(model: model)
        case .subscription(let id):
            SubscriptionDetailView(model: model, id: id).id(id)
        case .convert:
            ConvertView(model: model)
        }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("Library") {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    Label(filter.title, systemImage: filter.symbol)
                    .badge(filter == .all ? model.pendingCount : 0)
                    .tag(SidebarItem.library(filter))
                }
            }

            Section {
                if model.subscriptions.items.isEmpty {
                    Button {
                        model.subscribeRequest = .init(link: "")
                    } label: {
                        Label("Follow a Channel", systemImage: "plus")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("All Channels", systemImage: "person.2")
                        .badge(model.subscriptions.items.reduce(0) { $0 + $1.unseenCount })
                        .tag(SidebarItem.subscriptions)
                    ForEach(model.subscriptions.items) { sub in
                        Label {
                            Text(sub.title).lineLimit(1)
                        } icon: {
                            ChannelAvatar(url: sub.avatarURL, title: sub.title, size: 18)
                        }
                        .badge(sub.unseenCount)
                        .opacity(sub.isEnabled ? 1 : 0.55)
                        .tag(SidebarItem.subscription(sub.id))
                        .contextMenu {
                            Button("Check Now") { Task { await model.checkSubscription(sub.id) } }
                            Divider()
                            Button("Unfollow", role: .destructive) { model.unsubscribe(sub.id) }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Channels")
                    Spacer()
                    Button {
                        model.subscribeRequest = .init(link: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Follow a Channel")
                    .accessibilityLabel("Follow a Channel")
                }
            }

            Section("Tools") {
                Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                    .badge(model.stagedFiles.count + model.conversions.filter { $0.phase == .waiting || $0.phase == .converting }.count)
                    .tag(SidebarItem.convert)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom) { LibrarySummary(model: model) }
        .animation(.smooth(duration: 0.3), value: model.subscriptions.items.map(\.id))
    }
}

/// The library's footprint at the foot of the sidebar, with a slim meter; click for Storage.
private struct LibrarySummary: View {
    let model: AppModel
    @State private var hovering = false
    @State private var available: Int64?

    var body: some View {
        let items = model.history.items
        let bytes = items.reduce(Int64(0)) { $0 + ($1.byteCount ?? 0) }
        Button {
            model.showStorage = true
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Storage")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(bytes > 0 ? ByteSize.string(Double(bytes)) : "Empty")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    let total = Double(bytes + (available ?? 0))
                    let fraction = total > 0 ? Double(bytes) / total : 0
                    Capsule().fill(Color.primary.opacity(0.1))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.accentColor)
                                .frame(width: bytes > 0 ? max(4, geo.size.width * fraction) : 0)
                        }
                }
                .frame(height: 3)
                Text("\(items.count) item\(items.count == 1 ? "" : "s")" + (available.map { " · \(ByteSize.string(Double($0))) free" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Storage")
        .task(id: items.count) {
            let values = try? URL(fileURLWithPath: NSHomeDirectory())
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            available = values?.volumeAvailableCapacityForImportantUsage
        }
    }
}

/// One slim, quiet notice above the library when something needs attention.
private struct NoticeStrip: View {
    let model: AppModel
    private var toolchain: Toolchain { model.toolchain }

    var body: some View {
        Group {
            if toolchain.hasChecked && !toolchain.isReady {
                strip("shippingbox.fill", .orange,
                      "My Videos needs \(toolchain.missingTools.joined(separator: " and ")) to download.") {
                    Button("Finish Setup…") { model.showOnboarding = true }
                }
            } else if Diagnostics.shared.hasNewCrash {
                strip("exclamationmark.bubble.fill", .orange, "My Videos quit unexpectedly last time.") {
                    Button("Save Report…") {
                        Diagnostics.shared.exportReport(activityLog: model.activityLog, toolchain: toolchain)
                        Diagnostics.shared.markSeen()
                    }
                    Button("Dismiss") { Diagnostics.shared.markSeen() }
                }
            } else if toolchain.updateAvailable {
                strip("arrow.down.app.fill", .blue, "A yt-dlp update keeps downloads working as sites change.") {
                    if toolchain.operation == .updating {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Update") { Task { await toolchain.updateYtdlp(log: model.log) } }
                    }
                }
            } else if model.prefs.cookieSource != .none, case .problem(let message, _) = model.signIn.state {
                strip("person.crop.circle.badge.exclamationmark", .orange, message) {
                    SettingsLink { Text("Fix…") }
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func strip<Actions: View>(_ symbol: String, _ tint: Color, _ text: String,
                                      @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).lineLimit(2)
            Spacer()
            actions()
        }
        .font(.callout)
        .buttonStyle(.link)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(tint.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Activity inspector

private struct ActivityInspector: View {
    let log: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy Log")
                .disabled(log.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
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
            }
        }
    }
}
