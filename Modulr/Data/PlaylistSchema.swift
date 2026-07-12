import Foundation

/**
 * PlaylistSchema
 * Playlists and their ordered track references: uid public id, sort_order, ISO
 * timestamps, updated_at trigger, indexes and soft delete via deleted_at. The
 * track list is an ordered join rather than an inline array.
 */
enum PlaylistSchema {
    static let sql = """
    CREATE TABLE IF NOT EXISTS playlists (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        uid         TEXT NOT NULL UNIQUE,
        name        TEXT NOT NULL,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        deleted_at  TEXT DEFAULT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_playlists_uid ON playlists(uid);
    CREATE INDEX IF NOT EXISTS idx_playlists_deleted_at ON playlists(deleted_at);

    CREATE TRIGGER IF NOT EXISTS trg_playlists_updated_at
    AFTER UPDATE ON playlists
    FOR EACH ROW
    BEGIN
        UPDATE playlists
        SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE id = OLD.id;
    END;

    CREATE TABLE IF NOT EXISTS playlist_tracks (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_uid TEXT NOT NULL,
        track_url    TEXT NOT NULL,
        position     INTEGER NOT NULL DEFAULT 0,
        UNIQUE(playlist_uid, track_url)
    );

    CREATE INDEX IF NOT EXISTS idx_playlist_tracks_uid ON playlist_tracks(playlist_uid);
    """
}
