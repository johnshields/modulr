import Foundation
import AVFoundation

/**
 * LibraryScanner
 * Walks a folder, builds Track entries with metadata.
 * Async to use the modern AVAsset.load API (kills macOS 13 duration deprecation
 * warnings) and avoids blocking the main thread on large folders. Files are read
 * concurrently (bounded) so a 200-track folder is not gated on serial IO.
 */
enum LibraryScanner {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aif", "aiff", "flac", "aac"]

    private static let maxConcurrency = 8

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

        let files = entries.filter { file in
            let values = try? file.resourceValues(forKeys: Set(keys))
            let isFile = values?.isRegularFile ?? false
            return isFile && supportedExtensions.contains(file.pathExtension.lowercased())
        }
        return await buildConcurrently(files)
    }

    static func scanURLs(_ urls: [URL]) async -> [Track] {
        let fm = FileManager.default
        let files = urls.filter { file in
            fm.fileExists(atPath: file.path)
                && supportedExtensions.contains(file.pathExtension.lowercased())
        }
        return await buildConcurrently(files)
    }

    /// Build tracks with at most `maxConcurrency` files in flight, preserving input order.
    private static func buildConcurrently(_ files: [URL]) async -> [Track] {
        guard !files.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, Track).self) { group in
            var results = [Track?](repeating: nil, count: files.count)
            var next = 0
            while next < min(maxConcurrency, files.count) {
                let i = next
                group.addTask { (i, await buildTrack(files[i])) }
                next += 1
            }
            for await (index, track) in group {
                results[index] = track
                if next < files.count {
                    let i = next
                    group.addTask { (i, await buildTrack(files[i])) }
                    next += 1
                }
            }
            return results.compactMap { $0 }
        }
    }

    private static func buildTrack(_ file: URL) async -> Track {
        let values = try? file.resourceValues(forKeys: [
            .addedToDirectoryDateKey, .creationDateKey,
        ])
        let asset = AVURLAsset(url: file)
        let items = await MetadataReader.loadMetadata(asset)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        return Track(
            url: file,
            title: file.deletingPathExtension().lastPathComponent,
            artist: await MetadataReader.artist(items),
            duration: seconds,
            bpm: await MetadataReader.bpm(items),
            key: await MetadataReader.key(items),
            bitrate: await MetadataReader.bitrateKbps(asset, knownDuration: seconds),
            trackNumber: await MetadataReader.trackNumber(items),
            dateAdded: values?.addedToDirectoryDate ?? values?.creationDate
        )
    }
}
