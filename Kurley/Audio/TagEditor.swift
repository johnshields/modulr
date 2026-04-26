import Foundation
import ID3TagEditor

/**
 * TagEditor
 * Read and write ID3 tags on mp3 files
 */
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

enum TagIO {
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
        let editor = ID3TagEditor()
        let builder = ID32v3TagBuilder()

        if !meta.title.isEmpty {
            _ = builder.title(frame: ID3FrameWithStringContent(content: meta.title))
        }
        if !meta.artist.isEmpty {
            _ = builder.artist(frame: ID3FrameWithStringContent(content: meta.artist))
        }
        if !meta.album.isEmpty {
            _ = builder.album(frame: ID3FrameWithStringContent(content: meta.album))
        }
        if !meta.genre.isEmpty {
            _ = builder.genre(frame: ID3FrameGenre(genre: nil, description: meta.genre))
        }
        if let bpm = meta.bpm {
            _ = builder.beatsPerMinute(frame: ID3FrameWithIntegerContent(value: bpm))
        }
        if let year = meta.year {
            _ = builder.recordingYear(frame: ID3FrameWithIntegerContent(value: year))
        }

        let tag = builder.build()
        do {
            try editor.write(tag: tag, to: url.path)
        } catch {
            throw TagEditorError.writeFail
        }
    }

    /**
     * Rename file on disk. Returns new URL
     */
    static func rename(_ url: URL, to newBaseName: String) throws -> URL {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let newURL = dir.appendingPathComponent(trimmed).appendingPathExtension(ext)
        if newURL == url { return url }
        try FileManager.default.moveItem(at: url, to: newURL)
        return newURL
    }
}
