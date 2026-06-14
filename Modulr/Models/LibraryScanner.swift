import Foundation
import AVFoundation

/**
 * LibraryScanner
 * Walks a folder, builds Track entries with metadata.
 * Async to use the modern AVAsset.load API (kills macOS 13 duration deprecation
 * warnings) and avoids blocking the main thread on large folders.
 */
enum LibraryScanner {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "flac", "aac"]

    static func scan(_ folder: URL) async -> [Track] {
        let fm = FileManager.default
        // Top-level entries only — subdirectories are not descended into.
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        ) else { return [] }

        var found: [Track] = []
        for file in entries {
            let isFile = (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile, supportedExtensions.contains(file.pathExtension.lowercased()) else { continue }
            let asset = AVURLAsset(url: file)
            let items = await MetadataReader.loadMetadata(asset)
            let seconds = (try? await asset.load(.duration).seconds) ?? 0
            found.append(Track(
                url: file,
                title: file.deletingPathExtension().lastPathComponent,
                artist: await MetadataReader.artist(items),
                duration: seconds,
                bpm: await MetadataReader.bpm(items),
                key: await MetadataReader.key(items),
                bitrate: await MetadataReader.bitrateKbps(asset, knownDuration: seconds),
                trackNumber: await MetadataReader.trackNumber(items)
            ))
        }
        return found
    }

    /// Build Track entries from an explicit URL list (playlist path). Skips
    /// URLs that have gone missing on disk so a deleted file in a playlist
    /// silently drops out instead of crashing the scan.
    static func scanURLs(_ urls: [URL]) async -> [Track] {
        var found: [Track] = []
        let fm = FileManager.default
        for file in urls {
            guard fm.fileExists(atPath: file.path),
                  supportedExtensions.contains(file.pathExtension.lowercased())
            else { continue }
            let asset = AVURLAsset(url: file)
            let items = await MetadataReader.loadMetadata(asset)
            let seconds = (try? await asset.load(.duration).seconds) ?? 0
            found.append(Track(
                url: file,
                title: file.deletingPathExtension().lastPathComponent,
                artist: await MetadataReader.artist(items),
                duration: seconds,
                bpm: await MetadataReader.bpm(items),
                key: await MetadataReader.key(items),
                bitrate: await MetadataReader.bitrateKbps(asset, knownDuration: seconds),
                trackNumber: await MetadataReader.trackNumber(items)
            ))
        }
        return found
    }
}
