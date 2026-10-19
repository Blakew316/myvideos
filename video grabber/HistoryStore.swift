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

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("My Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { Self.supportDirectory.appendingPathComponent("History.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
        }
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        save()
    }

    func remove(ids: Set<HistoryItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func item(id: HistoryItem.ID) -> HistoryItem? {
        items.first { $0.id == id }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
