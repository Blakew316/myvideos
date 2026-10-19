//
//  Spotlight.swift
//  My Videos
//
//  Puts downloads in Spotlight by title and channel. Choosing a result opens My Videos
//  with that item selected and its Info showing.
//

import CoreSpotlight
import UniformTypeIdentifiers

@MainActor
enum SpotlightIndex {
    static let domain = "library"
    private static var pending: Task<Void, Never>?

    /// Rebuilds the index shortly after the library settles (changes come in bursts).
    static func schedule(_ items: [HistoryItem], enabled: Bool) {
        guard !AppModel.isTesting else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await rebuild(items, enabled: enabled)
        }
    }

    private static func rebuild(_ items: [HistoryItem], enabled: Bool) async {
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        guard enabled else { return }
        let searchable = items.filter { $0.cleanedUpAt == nil }.map(searchableItem)
        try? await index.indexSearchableItems(searchable)
    }

    private static func searchableItem(_ item: HistoryItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: item.isAudio ? .audio : .movie)
        attributes.title = item.title
        attributes.displayName = item.title
        var details: [String] = []
        if let uploader = item.uploader {
            details.append(uploader)
            attributes.artist = uploader
            attributes.authorNames = [uploader]
        }
        if let duration = item.duration, duration > 0 {
            details.append(Timecode.string(duration))
            attributes.duration = NSNumber(value: duration)
        }
        attributes.contentDescription = details.joined(separator: " · ")
        attributes.addedDate = item.date
        attributes.lastUsedDate = item.lastPlayedAt
        if let thumbnail = item.thumbnailURL, thumbnail.isFileURL { attributes.thumbnailURL = thumbnail }
        attributes.keywords = [item.uploader, item.isAudio ? "music" : "video"].compactMap { $0 }
        return CSSearchableItem(uniqueIdentifier: item.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
    }
}
