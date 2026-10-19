//
//  Sync.swift
//  My Videos
//

import Foundation
import Observation

/// Everything shared between Macs, stored as one file in iCloud Drive.
nonisolated struct SyncPayload: Codable, Sendable, Equatable {
    var history: [HistoryItem] = []
    var historyTombstones: Set<UUID> = []
    var subscriptions: [Subscription] = []
    var subscriptionTombstones: Set<UUID> = []
    var settings: SyncedSettings?
}

/// Pure merge rules, kept separate so they're easy to test.
nonisolated enum SyncMerge {
    static let historyLimit = 2000

    static func merge(local: SyncPayload, remote: SyncPayload) -> SyncPayload {
        var result = SyncPayload()

        result.historyTombstones = local.historyTombstones.union(remote.historyTombstones)
        var historyByID: [UUID: HistoryItem] = [:]
        for item in remote.history + local.history { historyByID[item.id] = item }  // local wins
        result.history = historyByID.values
            .filter { !result.historyTombstones.contains($0.id) }
            .sorted { $0.date > $1.date }
        if result.history.count > historyLimit { result.history = Array(result.history.prefix(historyLimit)) }

        result.subscriptionTombstones = local.subscriptionTombstones.union(remote.subscriptionTombstones)
        var subsByID: [UUID: Subscription] = [:]
        for sub in local.subscriptions { subsByID[sub.id] = sub }
        for sub in remote.subscriptions {
            guard let mine = subsByID[sub.id] else { subsByID[sub.id] = sub; continue }
            subsByID[sub.id] = mergeSubscription(mine, sub)
        }
        result.subscriptions = subsByID.values
            .filter { !result.subscriptionTombstones.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        switch (local.settings, remote.settings) {
        case let (l?, r?): result.settings = r.modified > l.modified ? r : l
        case let (l, r):   result.settings = l ?? r
        }
        return result
    }

    /// Newer edits win for choices; what each Mac has already seen is combined, so an
    /// upload is only downloaded once — by whichever Mac checks first.
    static func mergeSubscription(_ a: Subscription, _ b: Subscription) -> Subscription {
        var merged = a.modifiedAt >= b.modifiedAt ? a : b
        let other = a.modifiedAt >= b.modifiedAt ? b : a
        merged.seenIDs = Array(NSOrderedSet(array: other.seenIDs + merged.seenIDs)) as? [String] ?? merged.seenIDs
        merged.downloadedIDs = Array(NSOrderedSet(array: other.downloadedIDs + merged.downloadedIDs)) as? [String] ?? merged.downloadedIDs
        if (other.lastChecked ?? .distantPast) > (merged.lastChecked ?? .distantPast) {
            merged.lastChecked = other.lastChecked
            merged.recent = other.recent
        }
        merged.trim()
        return merged
    }
}

/// Keeps history, subscriptions and download settings in step across Macs through
/// iCloud Drive — no special entitlement needed, since it's an ordinary folder.
@Observable
final class SyncService {
    enum Status: Equatable {
        case off, unavailable, syncing, synced(Date), failed(String)
    }

    private(set) var status: Status = .off
    private var pushTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var lastWritten: SyncPayload?

    static var iCloudDrive: URL? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var folder: URL? { iCloudDrive?.appendingPathComponent("My Videos", isDirectory: true) }
    private static var fileURL: URL? { folder?.appendingPathComponent("Library.json") }

    /// Starts periodic syncing (and syncs now) — or stops, if sync is off.
    func configure(enabled: Bool, model: AppModel) {
        timer?.cancel()
        guard enabled else {
            status = .off
            return
        }
        guard Self.iCloudDrive != nil else {
            status = .unavailable
            return
        }
        timer = Task { [weak self, weak model] in
            while !Task.isCancelled {
                guard let self, let model else { return }
                await self.sync(model: model)
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    /// Debounced push after a local change.
    func scheduleSync(model: AppModel) {
        guard model.prefs.iCloudSync else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self, weak model] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, let model else { return }
            await self.sync(model: model)
        }
    }

    func sync(model: AppModel) async {
        guard model.prefs.iCloudSync, let folder = Self.folder, let file = Self.fileURL else { return }
        guard status != .syncing else { return }
        status = .syncing

        let local = SyncPayload(history: model.history.items,
                                historyTombstones: model.history.tombstones,
                                subscriptions: model.subscriptions.items,
                                subscriptionTombstones: model.subscriptions.tombstones,
                                settings: model.prefs.syncedSettings)
        let result: Result<SyncPayload?, Error> = await Task.detached {
            Result { try Self.read(file: file, folder: folder) }
        }.value

        switch result {
        case .failure(let error):
            status = .failed(error.localizedDescription)
            return
        case .success(let remote):
            let merged = remote.map { SyncMerge.merge(local: local, remote: $0) } ?? local
            model.history.replace(with: merged.history, tombstones: merged.historyTombstones)
            model.subscriptions.replace(with: merged.subscriptions, tombstones: merged.subscriptionTombstones)
            if let settings = merged.settings { model.prefs.apply(settings) }

            if merged != remote {
                let writeResult: Result<Void, Error> = await Task.detached {
                    Result { try Self.write(merged, file: file, folder: folder) }
                }.value
                if case .failure(let error) = writeResult {
                    status = .failed(error.localizedDescription)
                    return
                }
            }
            lastWritten = merged
            status = .synced(Date())
        }
    }

    nonisolated private static func read(file: URL, folder: URL) throws -> SyncPayload? {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // Not downloaded to this Mac yet: ask iCloud for it and try again next round.
        let placeholder = folder.appendingPathComponent(".\(file.lastPathComponent).icloud")
        if !fm.fileExists(atPath: file.path) {
            if fm.fileExists(atPath: placeholder.path) {
                try? fm.startDownloadingUbiquitousItem(at: file)
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Waiting for iCloud to download your library."])
            }
            return nil
        }
        var data: Data?
        var coordinationError: NSError?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
            do { data = try Data(contentsOf: url) } catch { readError = error }
        }
        if let error = coordinationError ?? readError { throw error }
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncPayload.self, from: data)
    }

    nonisolated private static func write(_ payload: SyncPayload, file: URL, folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }
}
