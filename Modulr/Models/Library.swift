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
    static let libraryFolderReloaded = Notification.Name("modulr.libraryFolderReloaded")
}

enum LibrarySource: Equatable { case folder, playlist }

final class Library: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var favorites: Set<UUID> = []
    @Published var recents: [URL] = []
    @Published var favouriteFolders: [URL] = []
    @Published var currentFolder: URL?

    @Published var playlists: [Playlist] = []
    @Published var currentPlaylist: Playlist?
    @Published var source: LibrarySource = .folder

    private let store = RecentsStore()
    private let playlistStore = PlaylistStore()

    init() {
        recents = store.loadRecents()
        favouriteFolders = store.loadFavouriteFolders()
        playlists = playlistStore.loadAll()
        if let url = store.lastFolder { openFolder(url) }
    }

    // MARK: - Playlists

    func createPlaylist(name: String) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let playlist = Playlist(name: trimmed.isEmpty ? "New Playlist" : trimmed)
        playlists.append(playlist)
        playlists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        playlistStore.save(playlist)
        return playlist
    }

    func renamePlaylist(id: UUID, to newName: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].name = newName
        playlists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        playlistStore.save(playlists[idx])
        if currentPlaylist?.id == id { currentPlaylist = playlists[idx] }
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        playlistStore.delete(id: id)
        if currentPlaylist?.id == id {
            currentPlaylist = nil
            if source == .playlist, let folder = currentFolder { openFolder(folder) }
        }
    }

    func removeFromPlaylist(_ playlistID: UUID, trackURL: URL) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].trackURLs.removeAll { $0 == trackURL }
        playlistStore.save(playlists[idx])
        if currentPlaylist?.id == playlistID { openPlaylist(playlists[idx]) }
    }

    func addToPlaylist(_ playlistID: UUID, trackURLs: [URL]) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let existing = Set(playlists[idx].trackURLs)
        let added = trackURLs.filter { !existing.contains($0) }
        playlists[idx].trackURLs.append(contentsOf: added)
        playlistStore.save(playlists[idx])
        let total = playlists[idx].trackURLs.count
        let startOffset = total - added.count
        for (i, url) in added.enumerated() where TagService.supportsTags(url) {
            TagService.setTrackNumber(url, index: startOffset + i + 1, total: total)
        }
        if currentPlaylist?.id == playlistID { openPlaylist(playlists[idx]) }
    }

    func applyRenameMap(logLines: [String]) {
        guard let folder = currentFolder else { return }
        var renames: [URL: URL] = [:]
        for line in logLines where line.hasPrefix("RENAMED: ") {
            let body = String(line.dropFirst("RENAMED: ".count))
            let parts = body.components(separatedBy: " -> ")
            guard parts.count == 2 else { continue }
            let old = folder.appendingPathComponent(
                parts[0].trimmingCharacters(in: .whitespaces))
            let new = folder.appendingPathComponent(
                parts[1].trimmingCharacters(in: .whitespaces))
            renames[old] = new
        }
        guard !renames.isEmpty else { return }

        for (idx, var playlist) in playlists.enumerated() {
            var dirty = false
            for (urlIdx, url) in playlist.trackURLs.enumerated() {
                if let mapped = renames[url] {
                    playlist.trackURLs[urlIdx] = mapped
                    dirty = true
                }
            }
            if dirty {
                playlists[idx] = playlist
                playlistStore.save(playlist)
            }
        }
        if let cur = currentPlaylist,
           let refreshed = playlists.first(where: { $0.id == cur.id }) {
            currentPlaylist = refreshed
        }
    }

    func updatePlaylistURL(from old: URL, to new: URL) {
        guard old != new else { return }
        for (idx, var playlist) in playlists.enumerated() {
            var dirty = false
            for (urlIdx, url) in playlist.trackURLs.enumerated() where url == old {
                playlist.trackURLs[urlIdx] = new
                dirty = true
            }
            if dirty {
                playlists[idx] = playlist
                playlistStore.save(playlist)
            }
        }
        if let cur = currentPlaylist,
           let refreshed = playlists.first(where: { $0.id == cur.id }) {
            currentPlaylist = refreshed
        }
    }

    func reorderCurrentPlaylist(orderedURLs: [URL]) {
        guard let cur = currentPlaylist,
              let idx = playlists.firstIndex(where: { $0.id == cur.id }) else { return }
        var playlist = playlists[idx]
        let existing = Set(playlist.trackURLs)
        let filtered = orderedURLs.filter { existing.contains($0) }
        let missing = playlist.trackURLs.filter { !filtered.contains($0) }
        playlist.trackURLs = filtered + missing
        playlists[idx] = playlist
        playlistStore.save(playlist)
        currentPlaylist = playlist
    }

    struct ConsolidateResult {
        var moved = 0
        var alreadyThere = 0
        var renamed = 0
        var failed = 0
    }

    func consolidatePlaylist(id: UUID, to destination: URL) -> ConsolidateResult {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else {
            return ConsolidateResult()
        }
        var result = ConsolidateResult()
        let fm = FileManager.default
        let destPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let snapshot = playlists[idx].trackURLs
        for url in snapshot {
            let parentPath = url.deletingLastPathComponent()
                .standardizedFileURL.resolvingSymlinksInPath().path
            if parentPath == destPath {
                result.alreadyThere += 1
                continue
            }
            var target = destination.appendingPathComponent(url.lastPathComponent)
            var collision = 1
            while fm.fileExists(atPath: target.path) {
                let stem = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                target = destination
                    .appendingPathComponent("\(stem) (\(collision))")
                    .appendingPathExtension(ext)
                collision += 1
            }
            let wasRenamed = target.lastPathComponent != url.lastPathComponent
            do {
                try fm.moveItem(at: url, to: target)
                updatePlaylistURL(from: url, to: target)
                if wasRenamed { result.renamed += 1 }
                result.moved += 1
            } catch {
                result.failed += 1
            }
        }
        if currentPlaylist?.id == id,
           let refreshed = playlists.first(where: { $0.id == id }) {
            openPlaylist(refreshed)
        }
        return result
    }

    func reloadCurrent() {
        switch source {
        case .folder:
            if let folder = currentFolder { openFolder(folder) }
        case .playlist:
            if let p = currentPlaylist { openPlaylist(p) }
        }
    }

    func openPlaylist(_ playlist: Playlist) {
        currentPlaylist = playlist
        source = .playlist
        tracks = []
        NotificationCenter.default.post(name: .libraryFolderReloaded, object: nil)
        Task { [weak self] in
            let scanned = await LibraryScanner.scanURLs(playlist.trackURLs)
            let positioned = playlist.trackURLs.enumerated().compactMap { (idx, url) -> Track? in
                guard let t = scanned.first(where: { $0.url == url }) else { return nil }
                return t.with(trackNumber: .some(idx + 1))
            }
            await MainActor.run { [weak self] in
                self?.tracks = positioned
            }
        }
    }

    func isFavouriteFolder(_ url: URL) -> Bool {
        favouriteFolders.contains(url)
    }

    func toggleFavouriteFolder(_ url: URL) {
        if let idx = favouriteFolders.firstIndex(of: url) {
            favouriteFolders.remove(at: idx)
        } else {
            favouriteFolders.append(url)
        }
        store.saveFavouriteFolders(favouriteFolders)
    }

    func openFolder(_ url: URL) {
        source = .folder
        currentPlaylist = nil
        currentFolder = url
        store.setLastFolder(url)
        recents = store.addRecent(url, current: recents)
        tracks = []
        NotificationCenter.default.post(name: .libraryFolderReloaded, object: nil)
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

    func rename(_ id: UUID, to newName: String) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let oldURL = tracks[idx].url
        let newURL = try TagService.rename(oldURL, to: newName)
        let stem = newURL.deletingPathExtension().lastPathComponent
        if TagService.supportsTags(newURL) { TagService.setTitle(newURL, title: stem) }
        tracks[idx] = tracks[idx].with(url: newURL, title: stem)
        updatePlaylistURL(from: oldURL, to: newURL)
    }

    func deleteTrack(_ id: UUID) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: tracks[idx].url, resultingItemURL: &resultingURL)
        tracks.remove(at: idx)
        favorites.remove(id)
    }

    func updateTags(_ id: UUID, meta: TrackMeta) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let original = tracks[idx]
        var workingURL = original.url
        let currentStem = workingURL.deletingPathExtension().lastPathComponent

        if !meta.title.isEmpty && meta.title != currentStem {
            workingURL = try TagService.rename(workingURL, to: meta.title)
            updatePlaylistURL(from: original.url, to: workingURL)
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

    func setArtwork(_ url: URL, imageData: Data, mime: String) {
        TagService.setArtwork(url, imageData: imageData, mime: mime)
        NotificationCenter.default.post(name: .artworkChanged, object: url, userInfo: ["data": imageData])
    }

    func removeArtwork(_ url: URL) {
        TagService.removeArtwork(url)
        NotificationCenter.default.post(name: .artworkChanged, object: url)
    }

    func renumberByTag(orderedIDs: [UUID], onProgress: ((Int, Int) -> Void)? = nil) {
        let total = orderedIDs.count
        var newOrder: [Track] = []
        newOrder.reserveCapacity(total)
        for (i, id) in orderedIDs.enumerated() {
            guard let idx = tracks.firstIndex(where: { $0.id == id }) else { continue }
            let index = i + 1
            TagService.setTrackNumber(tracks[idx].url, index: index, total: total)
            newOrder.append(tracks[idx].with(trackNumber: .some(index)))
            onProgress?(index, total)
        }
        let orderedSet = Set(orderedIDs)
        let leftovers = tracks.filter { !orderedSet.contains($0.id) }
        DispatchQueue.main.async { [newOrder, leftovers] in
            self.tracks = newOrder + leftovers
        }
    }

}
