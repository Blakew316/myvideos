//
//  ContentView.swift
//  My Videos
//

import SwiftUI
import AppKit
import Combine

/// The main window: sidebar navigation, the selected page, and the activity inspector.
struct ContentView: View {
    @Bindable private var model = AppModel.shared
    @State private var showActivity = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 820, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showActivity.toggle()
                } label: {
                    Label("Activity", systemImage: "sidebar.trailing")
                }
                .help(showActivity ? "Hide Activity" : "Show Activity")
            }
        }
        .inspector(isPresented: $showActivity) {
            ActivityInspector(log: model.activityLog)
                .inspectorColumnWidth(min: 280, ideal: 360, max: 600)
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(model: model)
        }
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
        switch model.selection ?? .download {
        case .download:            ComposerView(model: model)
        case .queue:               QueueView(model: model)
        case .history:             HistoryView(model: model)
        case .convert:             ConvertView(model: model)
        case .subscriptions:       SubscriptionsOverview(model: model)
        case .subscription(let id): SubscriptionDetailView(model: model, id: id).id(id)
        }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("Library") {
                Label("Download", systemImage: "arrow.down.circle")
                    .tag(SidebarItem.download)
                Label("Queue", systemImage: "list.bullet.rectangle")
                    .badge(model.pendingCount)
                    .tag(SidebarItem.queue)
                Label("History", systemImage: "clock")
                    .tag(SidebarItem.history)
            }

            Section {
                Label("All Subscriptions", systemImage: "dot.radiowaves.left.and.right")
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
                        Button("Unsubscribe", role: .destructive) { model.unsubscribe(sub.id) }
                    }
                }
            } header: {
                HStack {
                    Text("Subscriptions")
                    Spacer()
                    Button {
                        model.subscribeRequest = .init(link: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add Subscription")
                    .accessibilityLabel("Add Subscription")
                }
            }

            Section("Tools") {
                Label("Convert", systemImage: "wand.and.sparkles")
                    .badge(model.stagedFiles.count + model.conversions.filter { $0.phase == .waiting || $0.phase == .converting }.count)
                    .tag(SidebarItem.convert)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom) {
            if let job = model.activeJob, model.selection != .queue {
                SidebarActivity(job: job, remaining: model.pendingCount) {
                    model.selection = .queue
                }
                .padding(10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: model.activeJob?.id)
        .animation(.smooth(duration: 0.3), value: model.subscriptions.items.map(\.id))
    }
}

/// Compact progress in the sidebar, like Mail's activity indicator.
private struct SidebarActivity: View {
    let job: DownloadJob
    let remaining: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(remaining > 1 ? "Downloading \(remaining) items" : "Downloading")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if !job.progressIsIndeterminate {
                        Text(job.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                JobProgressBar(job: job)
                Text(job.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
        .help("Show Queue")
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
