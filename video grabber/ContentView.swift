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
        .inspector(isPresented: $model.showInspector) {
            LibraryInspector(model: model)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 520)
                .toolbar {
                    Button {
                        model.showInspector.toggle()
                    } label: {
                        Label("Show Info", systemImage: "info.circle")
                    }
                    .help("Show Info (⌘I)")
                }
        }
        .sheet(item: $model.collectionEditor) { request in
            CollectionEditor(model: model, existing: request.existing, smart: request.smart, initialItemIDs: request.itemIDs)
        }
        .onChange(of: model.selection) {
            // Keep only selected items that are still in view on the new page.
            let scope = model.selection.flatMap { LibraryScope($0) }
            model.librarySelection = model.librarySelection.filter { id in
                guard let scope, let item = model.history.item(id: id) else { return false }
                return scope.includes(item, collections: model.collections)
            }
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
            LibraryView(model: model, scope: .filter(filter))
                .id(filter)
                .safeAreaInset(edge: .top, spacing: 0) { NoticeStrip(model: model) }
        case .collection(let id):
            if model.collections.collection(id: id) != nil {
                LibraryView(model: model, scope: .collection(id)).id(id)
            } else {
                ContentUnavailableView("Collection Not Found", systemImage: "rectangle.stack")
            }
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

            Section {
                ForEach(model.collections.items) { collection in
                    CollectionRow(collection: collection, model: model)
                        .tag(SidebarItem.collection(collection.id))
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Menu {
                        Button("New Collection") { model.collectionEditor = .init() }
                        Button("New Smart Collection") { model.collectionEditor = .init(smart: true) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("New Collection")
                    .accessibilityLabel("New Collection")
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

// MARK: - Collections

/// A collection in the sidebar. Drop library items on a hand-made one to add them.
private struct CollectionRow: View {
    let collection: LibraryCollection
    let model: AppModel
    @State private var isTargeted = false

    var body: some View {
        Label(collection.name, systemImage: collection.symbol)
            .lineLimit(1)
            .badge(count)
            .padding(.vertical, 1)
            .background {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-4)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard !collection.isSmart else { return false }
                let ids = droppedItemIDs(urls)
                guard !ids.isEmpty else { return false }
                model.collections.add(itemIDs: ids, to: collection.id)
                return true
            } isTargeted: { isTargeted = $0 && !collection.isSmart }
            .contextMenu {
                if collection.isSmart {
                    Button("Edit Smart Collection…") { model.collectionEditor = .init(existing: collection, smart: true) }
                } else {
                    Button("Rename…") { model.collectionEditor = .init(existing: collection) }
                }
                Divider()
                Button("Delete Collection", role: .destructive) {
                    if model.selection == .collection(collection.id) { model.selection = .home }
                    model.collections.delete(collection.id)
                }
            }
    }

    private var count: Int {
        model.history.items.filter { collection.includes($0) }.count
    }

    /// Items dragged from the library are known by ID; files from Finder are matched by path.
    private func droppedItemIDs(_ urls: [URL]) -> [UUID] {
        if !model.draggingItemIDs.isEmpty {
            defer { model.draggingItemIDs = [] }
            return model.draggingItemIDs
        }
        let paths = Set(urls.filter(\.isFileURL).map(\.path))
        return model.history.items.filter { $0.filePaths.contains(where: paths.contains) }.map(\.id)
    }
}
