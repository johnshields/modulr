import Foundation

/**
 * URL helpers shared by the enhancement modals (Convert / Brighten / Loudness)
 * and any future file ops that need to derive sibling paths. Pure Foundation,
 * no UI or domain coupling — lives outside Views/Models on purpose.
 */
extension URL {
    /// Returns `<stem><suffix>.<ext>` in the same directory. Used for the
    /// `_bright` / `_loud` sibling files produced by ffmpeg before the user
    /// commits replacing the original.
    func sibling(suffix: String) -> URL {
        let dir = deletingLastPathComponent()
        let stem = deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem)\(suffix)")
            .appendingPathExtension(pathExtension)
    }

    /// Returns the URL with its path extension replaced (e.g. wav -> mp3).
    func changingExtension(to ext: String) -> URL {
        deletingPathExtension().appendingPathExtension(ext)
    }
}
