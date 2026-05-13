import Foundation
import ID3TagEditor

struct TrackMeta: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var year: Int?
    var genre: String = ""
    var bpm: Int?
}

enum TagEditorError: Error {
    case unsupportedFormat
    case writeFail
}

/**
 * TagService
 * Reads ID3 tags via ID3TagEditor.
 * Writes via Python/mutagen so artwork and other frames are preserved.
 */
enum TagService {
    static func isMP3(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "mp3"
    }

    static func read(_ url: URL) throws -> TrackMeta {
        guard isMP3(url) else { throw TagEditorError.unsupportedFormat }
        let editor = ID3TagEditor()
        let data = try Data(contentsOf: url)
        guard let tag = try editor.read(mp3: data) else { return TrackMeta() }
        var meta = TrackMeta()

        if let f = tag.frames[.title] as? ID3FrameWithStringContent { meta.title = f.content }
        if let f = tag.frames[.artist] as? ID3FrameWithStringContent { meta.artist = f.content }
        if let f = tag.frames[.album] as? ID3FrameWithStringContent { meta.album = f.content }
        if let f = tag.frames[.genre] as? ID3FrameGenre { meta.genre = f.description ?? "" }
        if let f = tag.frames[.beatsPerMinute] as? ID3FrameWithIntegerContent { meta.bpm = f.value }
        if let f = tag.frames[.recordingYear] as? ID3FrameWithIntegerContent { meta.year = f.value }
        return meta
    }

    static func write(_ meta: TrackMeta, to url: URL) throws {
        guard isMP3(url) else { throw TagEditorError.unsupportedFormat }
        if !meta.title.isEmpty { setTitle(url, title: meta.title) }
        if !meta.artist.isEmpty { setTag(url, frame: "artist", value: meta.artist) }
        if !meta.album.isEmpty { setTag(url, frame: "album", value: meta.album) }
        if !meta.genre.isEmpty { setTag(url, frame: "genre", value: meta.genre) }
        if let bpm = meta.bpm { setTag(url, frame: "bpm", value: String(bpm)) }
        if let year = meta.year { setTag(url, frame: "year", value: String(year)) }
    }

    static func setTitle(_ url: URL, title: String) {
        PythonRunner.shared.runSync(["--set-title", url.path, title])
    }

    static func setArtwork(_ url: URL, imageData: Data, mime: String) {
        PythonRunner.shared.runSync(["--set-artwork", url.path, "/dev/stdin", mime], stdin: imageData)
    }

    static func removeArtwork(_ url: URL) {
        PythonRunner.shared.runSync(["--remove-artwork", url.path])
    }

    /**
     * Rename file on disk. Returns new URL.
     */
    static func rename(_ url: URL, to newBaseName: String) throws -> URL {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return url }
        let dir = url.deletingLastPathComponent()
        let newURL = dir.appendingPathComponent(trimmed).appendingPathExtension(url.pathExtension)
        if newURL == url { return url }
        try FileManager.default.moveItem(at: url, to: newURL)
        return newURL
    }

    /**
     * Per-frame setter via Python/mutagen — preserves all other frames including artwork.
     */
    private static func setTag(_ url: URL, frame: String, value: String) {
        PythonRunner.shared.runSync(["--set-tag", url.path, frame, value])
    }
}

/**
 * Backwards-compat alias so older call sites still compile.
 */
typealias TagIO = TagService
