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
            switch model.selection ?? .download {
            case .download: ComposerView(model: model)
            case .queue:    QueueView(model: model)
            case .history:  HistoryView(model: model)
            }
        }
        .frame(minWidth: 760, minHeight: 600)
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
        }
        .onAppear { model.checkClipboard() }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            Label("Download", systemImage: "arrow.down.circle")
                .tag(SidebarItem.download)
            Label("Queue", systemImage: "list.bullet.rectangle")
                .badge(model.pendingCount)
                .tag(SidebarItem.queue)
            Label("History", systemImage: "clock")
                .tag(SidebarItem.history)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
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
                                       description: Text("Technical details from yt-dlp appear here while downloads run."))
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
