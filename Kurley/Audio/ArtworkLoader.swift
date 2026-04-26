import Foundation
import AVFoundation
import AppKit

/**
 * ArtworkLoader
 * Extract embedded artwork from audio file via AVAsset metadata
 */
enum ArtworkLoader {
    static func load(_ url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.commonMetadata)
            let artItems = AVMetadataItem.metadataItems(from: metadata, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common)
            for item in artItems {
                if let data = try await item.load(.dataValue), let img = NSImage(data: data) {
                    return img
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
