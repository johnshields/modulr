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
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .addedToDirectoryDateKey, .creationDateKey,
        ]
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        ) else { return [] }

        var found: [Track] = []
        for file in entries {
            let values = try? file.resourceValues(forKeys: Set(keys))
            let isFile = values?.isRegularFile ?? false
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
                trackNumber: await MetadataReader.trackNumber(items),
                dateAdded: values?.addedToDirectoryDate ?? values?.creationDate
            ))
        }
        return found
    }

    static func scanURLs(_ urls: [URL]) async -> [Track] {
        var found: [Track] = []
        let fm = FileManager.default
        for file in urls {
            guard fm.fileExists(atPath: file.path),
                  supportedExtensions.contains(file.pathExtension.lowercased())
            else { continue }
            let values = try? file.resourceValues(forKeys: [
                .addedToDirectoryDateKey, .creationDateKey,
            ])
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
                trackNumber: await MetadataReader.trackNumber(items),
                dateAdded: values?.addedToDirectoryDate ?? values?.creationDate
            ))
        }
        return found
    }
}
