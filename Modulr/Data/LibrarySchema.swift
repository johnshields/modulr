import Foundation

/**
 * LibrarySchema
 * Recents, favourites and simple key-value settings. Each table carries the
 * standard id / uid / created_at / updated_at fields with an updated_at trigger;
 * favourites also soft-delete via deleted_at. Recents order by updated_at (last
 * opened) and are hard-trimmed to a cap.
 */
enum LibrarySchema {
    static let sql = """
    CREATE TABLE IF NOT EXISTS settings (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        uid        TEXT NOT NULL UNIQUE,
        key        TEXT NOT NULL UNIQUE,
        value      TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
    );

    CREATE TRIGGER IF NOT EXISTS trg_settings_updated_at
    AFTER UPDATE ON settings FOR EACH ROW
    BEGIN
        UPDATE settings SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = OLD.id;
    END;

    CREATE TABLE IF NOT EXISTS recents (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        uid        TEXT NOT NULL UNIQUE,
        path       TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
    );

    CREATE TRIGGER IF NOT EXISTS trg_recents_updated_at
    AFTER UPDATE ON recents FOR EACH ROW
    BEGIN
        UPDATE recents SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = OLD.id;
    END;

    CREATE TABLE IF NOT EXISTS favourites (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        uid        TEXT NOT NULL UNIQUE,
        kind       TEXT NOT NULL,
        path       TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        deleted_at TEXT DEFAULT NULL,
        UNIQUE(kind, path)
    );

    CREATE INDEX IF NOT EXISTS idx_favourites_kind ON favourites(kind);
    CREATE INDEX IF NOT EXISTS idx_favourites_deleted_at ON favourites(deleted_at);

    CREATE TRIGGER IF NOT EXISTS trg_favourites_updated_at
    AFTER UPDATE ON favourites FOR EACH ROW
    BEGIN
        UPDATE favourites SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = OLD.id;
    END;
    """
}
