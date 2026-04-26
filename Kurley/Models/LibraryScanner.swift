import Foundation
import AVFoundation

/**
 * LibraryScanner
 * Walks a folder, builds Track entries with metadata
 */
enum LibraryScanner {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "flac", "aac"]

    static func scan(_ folder: URL) -> [Track] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
        var found: [Track] = []
        for case let file as URL in enumerator {
            guard supportedExtensions.contains(file.pathExtension.lowercased()) else { continue }
            let asset = AVURLAsset(url: file)
            found.append(Track(
                url: file,
                title: file.deletingPathExtension().lastPathComponent,
                artist: MetadataReader.artist(asset),
                duration: CMTimeGetSeconds(asset.duration),
                bpm: MetadataReader.bpm(asset),
                key: MetadataReader.key(asset),
                bitrate: MetadataReader.bitrateKbps(asset)
            ))
        }
        return found
    }
}
