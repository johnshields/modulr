import Foundation
import AVFoundation
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
 * Reads ID3 tags via ID3TagEditor for mp3 and AVFoundation metadata for m4a/wav.
 * Writes are uniformly routed through Python/mutagen, which dispatches by extension
 * so artwork and other frames are preserved across all supported formats.
 */
enum TagService {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "mp4", "aac", "aif", "aiff"]

    static func supportsTags(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func isMP3(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "mp3"
    }

    static func read(_ url: URL) throws -> TrackMeta {
        guard supportsTags(url) else { throw TagEditorError.unsupportedFormat }
        if isMP3(url) {
            return try readMP3(url)
        }
        return readViaAVAsset(url)
    }

    private static func readMP3(_ url: URL) throws -> TrackMeta {
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

    /**
     * AVAsset fallback for m4a/wav. Reads common iTunes-style atoms.
     * Sync wrapper around the async load(.metadata) call since callers expect throws-only.
     */
    private static func readViaAVAsset(_ url: URL) -> TrackMeta {
        let asset = AVURLAsset(url: url)
        let items = readMetadataItemsSync(asset)
        var meta = TrackMeta()
        for item in items {
            let id = item.identifier?.rawValue ?? ""
            let common = item.commonKey?.rawValue ?? ""
            guard let value = readStringSync(item) else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // ID3 (mp3, wav), MP4 (m4a) and common AVAsset keys all surface here.
            if matches(id: id, common: common, needles: ["TIT2", "nam", "title"]) {
                meta.title = trimmed
            } else if matches(id: id, common: common, needles: ["TPE1", "ART", "artist"]) {
                meta.artist = trimmed
            } else if matches(id: id, common: common, needles: ["TALB", "alb", "album"]) {
                meta.album = trimmed
            } else if matches(id: id, common: common, needles: ["TCON", "gen", "genre"]) {
                meta.genre = trimmed
            } else if matches(id: id, common: common, needles: ["TDRC", "TYER", "day", "creationDate", "recordingYear"]) {
                meta.year = Int(trimmed.prefix(4))
            } else if matches(id: id, common: common, needles: ["TBPM", "tmpo", "beatsPerMinute"]) {
                meta.bpm = Int(trimmed)
            }
        }
        return meta
    }

    private static func matches(id: String, common: String, needles: [String]) -> Bool {
        for n in needles {
            if id.lowercased().contains(n.lowercased()) { return true }
            if common.lowercased().contains(n.lowercased()) { return true }
        }
        return false
    }

    private static func readMetadataItemsSync(_ asset: AVURLAsset) -> [AVMetadataItem] {
        let sema = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: [AVMetadataItem] = []
        Task {
            result = (try? await asset.load(.metadata)) ?? []
            sema.signal()
        }
        sema.wait()
        return result
    }

    private static func readStringSync(_ item: AVMetadataItem) -> String? {
        if let number = item.numberValue {
            return number.stringValue
        }
        let sema = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: String?
        Task {
            result = try? await item.load(.stringValue)
            sema.signal()
        }
        sema.wait()
        return result
    }

    static func write(_ meta: TrackMeta, to url: URL) throws {
        guard supportsTags(url) else { throw TagEditorError.unsupportedFormat }
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

    /**
     * Write track-number tag (TRCK on ID3, trkn on MP4). Pass "5" or "5/12".
     * Rekordbox honours this so libraries survive without filename renumbering.
     */
    static func setTrackNumber(_ url: URL, index: Int, total: Int) {
        let value = "\(index)/\(total)"
        PythonRunner.shared.runSync(["--set-tag", url.path, "tracknum", value])
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
