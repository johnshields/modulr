import Foundation

/**
 * LibraryQueries
 * Named SQL for the settings, recents and favourites tables. Inserts carry a
 * uid; upserts touch a column so the updated_at trigger fires.
 */
enum LibraryQueries {
    static let getSetting = "SELECT value FROM settings WHERE key = ?"

    static let setSetting = """
        INSERT INTO settings (uid, key, value) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
    """

    static let recentsAll = "SELECT path FROM recents ORDER BY updated_at DESC LIMIT ?"

    static let recentUpsert = """
        INSERT INTO recents (uid, path) VALUES (?, ?)
        ON CONFLICT(path) DO UPDATE SET path = excluded.path
    """

    static let recentTrim = """
        DELETE FROM recents
        WHERE path NOT IN (SELECT path FROM recents ORDER BY updated_at DESC LIMIT ?)
    """

    static let favouritesByKind = """
        SELECT path FROM favourites
        WHERE kind = ? AND deleted_at IS NULL
        ORDER BY created_at ASC
    """

    static let favouriteInsert = """
        INSERT INTO favourites (uid, kind, path) VALUES (?, ?, ?)
        ON CONFLICT(kind, path) DO UPDATE SET deleted_at = NULL
    """

    static let favouriteClearKind = """
        UPDATE favourites
        SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE kind = ? AND deleted_at IS NULL
    """
}
