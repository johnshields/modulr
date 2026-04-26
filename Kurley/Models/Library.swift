import Foundation
import AVFoundation
import Combine

/**
 * Library
 * Tracks list, folder open, favorites, playlists
 * Persists last folder + recents in UserDefaults
 */
final class Library: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var favorites: Set<UUID> = []
    @Published var recents: [URL] = []
    @Published var currentFolder: URL?

    private let supportedExt: Set<String> = ["mp3", "m4a", "wav", "aiff", "flac", "aac"]
    private let defaults = UserDefaults.standard
    private let kLastFolder = "kurley.lastFolder"
    private let kRecents = "kurley.recents"

    init() {
        loadRecents()
        if let url = lastFolderURL() {
            openFolder(url)
        }
    }

    func openFolder(_ url: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        var found: [Track] = []
        for case let file as URL in enumerator {
            guard supportedExt.contains(file.pathExtension.lowercased()) else { continue }
            let asset = AVURLAsset(url: file)
            let dur = CMTimeGetSeconds(asset.duration)
            let bpm = readBPM(asset)
            let key = readKey(asset)
            let artist = readArtist(asset)
            found.append(Track(url: file, title: file.deletingPathExtension().lastPathComponent, artist: artist, duration: dur, bpm: bpm, key: key))
        }
        tracks = found
        currentFolder = url
        persistFolder(url)
        addRecent(url)
    }

    /**
     * Read BPM from ID3 TBPM tag or iTunes metadata
     */
    private func readArtist(_ asset: AVURLAsset) -> String? {
        for item in asset.metadata {
            if item.commonKey == .commonKeyArtist {
                if let s = item.stringValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                    return s
                }
            }
        }
        return nil
    }

    private func readKey(_ asset: AVURLAsset) -> String? {
        for item in asset.metadata {
            let key = item.identifier?.rawValue ?? ""
            if key.contains("TKEY") || key.lowercased().contains("initialkey") {
                if let s = item.stringValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                    return KeyNormalizer.toCamelot(s) ?? s
                }
            }
        }
        return nil
    }

    private func readBPM(_ asset: AVURLAsset) -> Int? {
        for item in asset.metadata {
            let key = item.identifier?.rawValue ?? ""
            if key.contains("TBPM") || key.lowercased().contains("bpm") || item.commonKey?.rawValue == "beatsPerMinute" {
                if let n = item.numberValue?.intValue { return n }
                if let s = item.stringValue, let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
            }
        }
        return nil
    }

    func toggleFavorite(_ id: UUID) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }

    /**
     * Rename file on disk + update track entry
     */
    func rename(_ id: UUID, to newName: String) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let newURL = try TagIO.rename(tracks[idx].url, to: newName)
        tracks[idx] = Track(url: newURL, title: newURL.deletingPathExtension().lastPathComponent,
                            artist: tracks[idx].artist,
                            duration: tracks[idx].duration, bpm: tracks[idx].bpm, key: tracks[idx].key)
    }

    /**
     * Run analyze.py --set-title to write TIT2 via mutagen (preserves artwork)
     */
    private func writeTitleViaPython(_ url: URL, title: String) {
        let scriptPath = "/Users/johnshields/Projects/kurley/scripts/analyze.py"
        let pythonPath = UserDefaults.standard.string(forKey: "kurley.pythonPath") ?? "/opt/homebrew/bin/python3"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = [scriptPath, "--set-title", url.path, title]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("set-title failed: \(error)")
        }
    }

    /**
     * Set/replace artwork on mp3 via mutagen (preserves all other frames)
     */
    func setArtwork(_ url: URL, imageData: Data, mime: String) {
        runSetArtwork(url: url, args: ["--set-artwork", url.path, "/dev/stdin", mime], stdin: imageData)
    }

    /**
     * Remove artwork from mp3
     */
    func removeArtwork(_ url: URL) {
        runSetArtwork(url: url, args: ["--remove-artwork", url.path], stdin: nil)
    }

    private func runSetArtwork(url: URL, args: [String], stdin: Data?) {
        let scriptPath = "/Users/johnshields/Projects/kurley/scripts/analyze.py"
        let pythonPath = UserDefaults.standard.string(forKey: "kurley.pythonPath") ?? "/opt/homebrew/bin/python3"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = [scriptPath] + args
        if let stdin {
            let inPipe = Pipe()
            task.standardInput = inPipe
            do {
                try task.run()
                inPipe.fileHandleForWriting.write(stdin)
                try? inPipe.fileHandleForWriting.close()
                task.waitUntilExit()
            } catch { print("artwork set fail: \(error)") }
        } else {
            do { try task.run(); task.waitUntilExit() }
            catch { print("artwork remove fail: \(error)") }
        }
    }

    /**
     * Renumber files: prepend NNN_ prefix in given order
     * Strips existing NNN_ prefix first
     */
    func renumber(orderedIDs: [UUID], padding: Int = 3) throws {
        var updated: [Track] = tracks
        for (i, id) in orderedIDs.enumerated() {
            guard let idx = updated.firstIndex(where: { $0.id == id }) else { continue }
            let url = updated[idx].url
            let stem = url.deletingPathExtension().lastPathComponent
            let strippedStem = stem.replacingOccurrences(
                of: #"^\d{2,4}_"#,
                with: "",
                options: .regularExpression
            )
            let prefix = String(format: "%0\(padding)d", i + 1)
            let newName = "\(prefix)_\(strippedStem)"
            let newURL = url.deletingLastPathComponent()
                .appendingPathComponent(newName)
                .appendingPathExtension(url.pathExtension)
            if newURL != url {
                try FileManager.default.moveItem(at: url, to: newURL)
            }
            // Sync ID3 title to filename stem via mutagen (preserves artwork + all other frames)
            if TagIO.isMP3(newURL) {
                writeTitleViaPython(newURL, title: newName)
            }
            updated[idx] = Track(
                url: newURL,
                title: newName,
                artist: updated[idx].artist,
                duration: updated[idx].duration,
                bpm: updated[idx].bpm,
                key: updated[idx].key
            )
        }
        tracks = updated
    }

    /**
     * Move file to Trash + remove from list
     */
    func deleteTrack(_ id: UUID) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: tracks[idx].url, resultingItemURL: &resultingURL)
        tracks.remove(at: idx)
        favorites.remove(id)
    }

    /**
     * Write tag changes + reload BPM/title from disk
     */
    func updateTags(_ id: UUID, meta: TrackMeta) throws {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        try TagIO.write(meta, to: tracks[idx].url)
        var t = tracks[idx]
        t.bpm = meta.bpm
        if !meta.title.isEmpty { t.title = meta.title }
        tracks[idx] = t
    }

    /**
     * Persistence
     */
    private func persistFolder(_ url: URL) {
        defaults.set(url.path, forKey: kLastFolder)
    }

    private func lastFolderURL() -> URL? {
        guard let path = defaults.string(forKey: kLastFolder) else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func addRecent(_ url: URL) {
        var list = recents.filter { $0 != url }
        list.insert(url, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        recents = list
        defaults.set(list.map(\.path), forKey: kRecents)
    }

    private func loadRecents() {
        let paths = defaults.stringArray(forKey: kRecents) ?? []
        recents = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
