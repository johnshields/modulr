import Foundation

/**
 * RecentsStore
 * SQLite-backed store for the last opened folder, recents and favourites in
 * `~/Library/Application Support/Modulr/`. Public surface is unchanged. Values
 * from the earlier UserDefaults store are imported once, then those keys cleared.
 */
final class RecentsStore {
    private let db: Database
    private let maxRecents = 10

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("Modulr", isDirectory: true)
        self.db = Database(path: root.appendingPathComponent("modulr.sqlite"))
        db.execScript(LibrarySchema.sql)
        migrateDefaults()
    }

    var lastFolder: URL? {
        guard let path = db.fetchOne(LibraryQueries.getSetting, [.text("last_folder")])?["value"] as? String
        else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func setLastFolder(_ url: URL) {
        db.exec(LibraryQueries.setSetting, [.text(UID.gen("STG")), .text("last_folder"), .text(url.path)])
    }

    func loadRecents() -> [URL] {
        paths(LibraryQueries.recentsAll, [.int(maxRecents)])
    }

    @discardableResult
    func addRecent(_ url: URL, current: [URL]) -> [URL] {
        db.exec(LibraryQueries.recentUpsert, [.text(UID.gen("RCT")), .text(url.path)])
        db.exec(LibraryQueries.recentTrim, [.int(maxRecents)])
        return loadRecents()
    }

    func loadFavouriteFolders() -> [URL] { favourites("folder") }
    func saveFavouriteFolders(_ urls: [URL]) { saveFavourites("folder", urls) }
    func loadFavouriteTracks() -> [URL] { favourites("track") }
    func saveFavouriteTracks(_ urls: [URL]) { saveFavourites("track", urls) }

    private func favourites(_ kind: String) -> [URL] {
        paths(LibraryQueries.favouritesByKind, [.text(kind)])
    }

    private func saveFavourites(_ kind: String, _ urls: [URL]) {
        db.transaction {
            db.exec(LibraryQueries.favouriteClearKind, [.text(kind)])
            for url in urls {
                db.exec(LibraryQueries.favouriteInsert, [.text(UID.gen("FAV")), .text(kind), .text(url.path)])
            }
        }
    }

    private func paths(_ sql: String, _ params: [Database.Value]) -> [URL] {
        db.fetchAll(sql, params)
            .compactMap { $0["path"] as? String }
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func migrateDefaults() {
        let d = UserDefaults.standard
        let keys = ["modulr.lastFolder", "modulr.recents",
                    "modulr.favouriteFolders", "modulr.favouriteTracks"]
        guard keys.contains(where: { d.object(forKey: $0) != nil }) else { return }
        if let last = d.string(forKey: "modulr.lastFolder") {
            setLastFolder(URL(fileURLWithPath: last))
        }
        // Reversed so the newest entry gets the latest updated_at.
        for path in (d.stringArray(forKey: "modulr.recents") ?? []).reversed() {
            db.exec(LibraryQueries.recentUpsert, [.text(UID.gen("RCT")), .text(path)])
        }
        saveFavourites("folder", (d.stringArray(forKey: "modulr.favouriteFolders") ?? [])
            .map { URL(fileURLWithPath: $0) })
        saveFavourites("track", (d.stringArray(forKey: "modulr.favouriteTracks") ?? [])
            .map { URL(fileURLWithPath: $0) })
        keys.forEach { d.removeObject(forKey: $0) }
    }
}
