//
//  HistoryStore.swift
//  My Videos
//

import Foundation
import Observation

/// Everything downloaded, newest first, saved to Application Support.
@Observable
final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    /// Removed item IDs, so iCloud sync doesn't bring them back from another Mac.
    private(set) var tombstones: Set<UUID> = []

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("My Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { Self.supportDirectory.appendingPathComponent("History.json") }
    private var tombstoneURL: URL { Self.supportDirectory.appendingPathComponent("History-Deleted.json") }

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL) {
            items = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: tombstoneURL) {
            tombstones = (try? decoder.decode(Set<UUID>.self, from: data)) ?? []
        }
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        save()
    }

    func remove(ids: Set<HistoryItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        tombstones.formUnion(ids)
        save()
    }

    func clear() {
        tombstones.formUnion(items.map(\.id))
        items.removeAll()
        save()
    }

    func update(_ id: HistoryItem.ID, _ change: (inout HistoryItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    func item(id: HistoryItem.ID) -> HistoryItem? {
        items.first { $0.id == id }
    }

    /// Replaces everything with a merged set from iCloud sync.
    func replace(with merged: [HistoryItem], tombstones newTombstones: Set<UUID>) {
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
