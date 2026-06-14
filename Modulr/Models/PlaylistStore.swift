import Foundation

/**
 * PlaylistStore
 * JSON persistence for playlists in `~/Library/Application Support/Modulr/`.
 * One file per playlist keyed by UUID so renames + reorders are atomic.
 */
final class PlaylistStore {
    private let folder: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("Modulr/Playlists", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.folder = root
    }

    func loadAll() -> [Playlist] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Playlist.self, from: $0) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ playlist: Playlist) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(playlist) else { return }
        let url = folder.appendingPathComponent("\(playlist.id.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    func delete(id: UUID) {
        let url = folder.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
