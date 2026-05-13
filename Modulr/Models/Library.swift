import Foundation
import AVFoundation
import Combine

/**
 * Library
 * Holds the current track list, favourites, recents.
 * Mutations route through TagService for tag/file ops; persistence delegated to RecentsStore.
 */
extension Notification.Name {
    static let artworkChanged = Notification.Name("modulr.artworkChanged")
}

final class Library: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var favorites: Set<UUID> = []
    @Published var recents: [URL] = []
    @Published var currentFolder: URL?

    private let store = RecentsStore()

    init() {
        recents = store.loadRecents()
        if let url = store.lastFolder { openFolder(url) }
    }

    func openFolder(_ url: URL) {
        // Surface folder metadata immediately; scan tracks off main thread.
        currentFolder = url
        store.setLastFolder(url)
        recents = store.addRecent(url, current: recents)
        tracks = []
        Task { [weak self] in
            let scanned = await LibraryScanner.scan(url)
            await MainActor.run { [weak self] in
                self?.tracks = scanned
            }
        }
    }

    func toggleFavorite(_ id: UUID) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }

    /**
     * Rename file on disk and sync ID3 title to match the new stem.
     */
    func rename(_ id: UUID, to newName: String) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let newURL = try TagService.rename(tracks[idx].url, to: newName)
        let stem = newURL.deletingPathExtension().lastPathComponent
        if TagService.isMP3(newURL) { TagService.setTitle(newURL, title: stem) }
        tracks[idx] = tracks[idx].with(url: newURL, title: stem)
    }

    /**
     * Move file to Trash + remove from list
     */
    func deleteTrack(_ id: UUID) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: tracks[idx].url, resultingItemURL: &resultingURL)
        tracks.remove(at: idx)
        favorites.remove(id)
    }

    /**
     * Write tag changes. If meta.title differs from filename stem, also rename file to match.
     */
    func updateTags(_ id: UUID, meta: TrackMeta) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let original = tracks[idx]
        var workingURL = original.url
        let currentStem = workingURL.deletingPathExtension().lastPathComponent

        if !meta.title.isEmpty && meta.title != currentStem {
            workingURL = try TagService.rename(workingURL, to: meta.title)
        }
        try TagService.write(meta, to: workingURL)

        let resolvedTitle = workingURL.deletingPathExtension().lastPathComponent
        tracks[idx] = original.with(
            url: workingURL,
            title: resolvedTitle,
            artist: meta.artist.isEmpty ? original.artist : meta.artist,
            bpm: meta.bpm
        )
    }

    /**
     * Set/replace artwork on mp3 (preserves all other frames).
     * Posts ArtworkChanged so observing views can refresh.
     */
    func setArtwork(_ url: URL, imageData: Data, mime: String) {
        TagService.setArtwork(url, imageData: imageData, mime: mime)
        NotificationCenter.default.post(name: .artworkChanged, object: url, userInfo: ["data": imageData])
    }

    func removeArtwork(_ url: URL) {
        TagService.removeArtwork(url)
        NotificationCenter.default.post(name: .artworkChanged, object: url)
    }

    /**
     * Renumber files: prepend NNN_ prefix in given order, sync ID3 title to filename.
     * Calls onProgress(done, total) after each file is processed.
     */
    func renumber(orderedIDs: [UUID], padding: Int = 3, onProgress: ((Int, Int) -> Void)? = nil) throws {
        var updated: [Track] = tracks
        let total = orderedIDs.count
        for (i, id) in orderedIDs.enumerated() {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            let url = updated[idx].url
            let stem = url.deletingPathExtension().lastPathComponent
            let strippedStem = stem.replacingOccurrences(
                of: #"^\d{2,4}_"#,
                with: "",
                options: .regularExpression
            )
            let prefix = String(format: "%0\(padding)d", i + 1)
            let newName = "\(prefix)_\(strippedStem)"
            let newURL = url.deletingLastPathComponent()
                .appendingPathComponent(newName)
                .appendingPathExtension(url.pathExtension)
            if newURL != url {
                try FileManager.default.moveItem(at: url, to: newURL)
            }
            if TagService.isMP3(newURL) { TagService.setTitle(newURL, title: newName) }
            updated[idx] = updated[idx].with(url: newURL, title: newName)
            onProgress?(i + 1, total)
        }
        tracks = updated
    }
}
