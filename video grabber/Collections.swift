//
//  Collections.swift
//  My Videos
//
//  Your own groupings in the sidebar: collections you fill by hand (drag items onto
//  them or use Add to Collection) and smart collections that fill themselves from rules.
//

import SwiftUI
import Observation

// MARK: - Model

nonisolated struct LibraryCollection: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    /// Items added by hand (ignored for smart collections).
    var itemIDs: [UUID] = []
    /// Present for smart collections.
    var rules: SmartRules?
    var createdAt = Date()
    var modifiedAt = Date()

    var isSmart: Bool { rules != nil }
    var symbol: String { isSmart ? "gearshape" : "rectangle.stack" }

    func includes(_ item: HistoryItem) -> Bool {
        if let rules { return rules.matches(item) }
        return itemIDs.contains(item.id)
    }
}

/// Every rule that's set must match.
nonisolated struct SmartRules: Codable, Sendable, Equatable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case any, video, audio
        var id: String { rawValue }
        var title: String { self == .any ? "Any" : self == .video ? "Videos" : "Music" }
    }

    enum Watched: String, Codable, Sendable, CaseIterable, Identifiable {
        case any, unwatched, inProgress, watched
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: return "Any"
            case .unwatched: return "Unwatched"
            case .inProgress: return "Started, Not Finished"
            case .watched: return "Watched"
            }
        }
    }

    var kind: Kind = .any
    var watched: Watched = .any
    /// Matches when the channel name contains this text (case-insensitive).
    var channel: String = ""
    var minMinutes: Int = 0
    /// 0 means no limit.
    var maxMinutes: Int = 0
    /// Added in the last N days; 0 means any time.
    var addedWithinDays: Int = 0

    func matches(_ item: HistoryItem, now: Date = Date()) -> Bool {
        switch kind {
        case .any: break
        case .video: if item.isAudio { return false }
        case .audio: if !item.isAudio { return false }
        }
        switch watched {
        case .any: break
        case .unwatched: if item.isWatched || item.watchProgress != nil { return false }
        case .inProgress: if item.isWatched || item.watchProgress == nil { return false }
        case .watched: if !item.isWatched { return false }
        }
        let channel = channel.trimmingCharacters(in: .whitespaces)
        if !channel.isEmpty, !(item.uploader?.localizedCaseInsensitiveContains(channel) ?? false) { return false }
        let minutes = (item.duration ?? 0) / 60
        if minMinutes > 0, minutes < Double(minMinutes) { return false }
        if maxMinutes > 0, minutes > Double(maxMinutes) { return false }
        if addedWithinDays > 0, item.date < now.addingTimeInterval(-Double(addedWithinDays) * 86400) { return false }
        return true
    }
}

// MARK: - Store

@Observable
final class CollectionStore {
    private(set) var items: [LibraryCollection] = []
    /// Deleted collection IDs, so iCloud sync doesn't bring them back.
    private(set) var tombstones: Set<UUID> = []

    private var fileURL: URL { HistoryStore.supportDirectory.appendingPathComponent("Collections.json") }
    private var tombstoneURL: URL { HistoryStore.supportDirectory.appendingPathComponent("Collections-Deleted.json") }

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL) {
            items = (try? decoder.decode([LibraryCollection].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: tombstoneURL) {
            tombstones = (try? decoder.decode(Set<UUID>.self, from: data)) ?? []
        }
    }

    func collection(id: UUID) -> LibraryCollection? { items.first { $0.id == id } }

    func add(_ collection: LibraryCollection) {
        items.append(collection)
        save()
    }

    func update(_ id: UUID, _ change: (inout LibraryCollection) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        items[index].modifiedAt = Date()
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        tombstones.insert(id)
        save()
    }

    /// Adds items to a hand-made collection, keeping their order and skipping repeats.
    func add(itemIDs: [UUID], to id: UUID) {
        update(id) { collection in
            for itemID in itemIDs where !collection.itemIDs.contains(itemID) { collection.itemIDs.append(itemID) }
        }
    }

    func remove(itemIDs: Set<UUID>, from id: UUID) {
        update(id) { $0.itemIDs.removeAll { itemIDs.contains($0) } }
    }

    func replace(with merged: [LibraryCollection], tombstones newTombstones: Set<UUID>) {
        guard merged != items || newTombstones != tombstones else { return }
        items = merged
        tombstones = newTombstones
        save(notify: false)
    }

    private func save(notify: Bool = true) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) { try? data.write(to: fileURL, options: .atomic) }
        if let data = try? encoder.encode(tombstones) { try? data.write(to: tombstoneURL, options: .atomic) }
        if notify { NotificationCenter.default.post(name: .myVideosLocalDataChanged, object: nil) }
    }
}

// MARK: - Editor

/// Creates or edits a collection. Smart collections show their rules as a form.
struct CollectionEditor: View {
    let model: AppModel
    /// Nil when creating.
    let existing: LibraryCollection?
    /// Items to start a new hand-made collection with (New Collection from Selection).
    var initialItemIDs: [UUID] = []
    @State private var name: String
    @State private var isSmart: Bool
    @State private var rules: SmartRules
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, existing: LibraryCollection?, smart: Bool, initialItemIDs: [UUID] = []) {
        self.model = model
        self.existing = existing
        self.initialItemIDs = initialItemIDs
        _name = State(initialValue: existing?.name ?? "")
        _isSmart = State(initialValue: existing?.isSmart ?? smart)
        _rules = State(initialValue: existing?.rules ?? SmartRules(watched: .unwatched))
    }

    private var matchCount: Int { model.history.items.filter { rules.matches($0) }.count }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text(isSmart ? "Smart Collection" : "Collection"))
                if isSmart {
                    Section {
                        Picker("Kind", selection: $rules.kind) {
                            ForEach(SmartRules.Kind.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Watched", selection: $rules.watched) {
                            ForEach(SmartRules.Watched.allCases) { Text($0.title).tag($0) }
                        }
                        TextField("Channel contains", text: $rules.channel, prompt: Text("Any channel"))
                        Picker("Longer than", selection: $rules.minMinutes) {
                            Text("Any length").tag(0)
                            ForEach([1, 5, 10, 20, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                        }
                        Picker("Shorter than", selection: $rules.maxMinutes) {
                            Text("Any length").tag(0)
                            ForEach([1, 5, 10, 20, 30, 60, 120], id: \.self) { Text("\($0) min").tag($0) }
                        }
                        Picker("Added", selection: $rules.addedWithinDays) {
                            Text("Any time").tag(0)
                            Text("Today").tag(1)
                            Text("In the last week").tag(7)
                            Text("In the last month").tag(30)
                            Text("In the last year").tag(365)
                        }
                    } header: {
                        Text("Include items that match all of these")
                    } footer: {
                        Text("\(matchCount) item\(matchCount == 1 ? "" : "s") match right now.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Create" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? (isSmart ? "Smart Collection" : "Collection") : trimmed
        if let existing {
            model.collections.update(existing.id) { collection in
                collection.name = finalName
                if isSmart { collection.rules = rules }
            }
        } else {
            let collection = LibraryCollection(name: finalName, itemIDs: isSmart ? [] : initialItemIDs,
                                               rules: isSmart ? rules : nil)
            model.collections.add(collection)
            model.selection = .collection(collection.id)
        }
        dismiss()
    }
}

/// Asks the main window to show the collection editor.
struct CollectionEditorRequest: Identifiable {
    let id = UUID()
    var existing: LibraryCollection?
    var smart = false
    var itemIDs: [UUID] = []
}
