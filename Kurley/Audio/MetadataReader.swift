import Foundation
import AVFoundation

/**
 * MetadataReader
 * Pulls common metadata fields out of AVURLAsset using the modern async API.
 * Callers load asset metadata once and pass the array in to avoid repeated IO.
 */
enum MetadataReader {
    static func loadMetadata(_ asset: AVURLAsset) async -> [AVMetadataItem] {
        (try? await asset.load(.metadata)) ?? []
    }

    static func bpm(_ items: [AVMetadataItem]) async -> Int? {
        for item in items where matches(item, idContains: "TBPM", commonKey: "beatsPerMinute") {
            if let number = await loadNumber(item) { return number.intValue }
            if let trimmed = await loadString(item)?.trimmingCharacters(in: .whitespaces),
               let n = Int(trimmed) { return n }
        }
        return nil
    }

    static func key(_ items: [AVMetadataItem]) async -> String? {
        for item in items where matches(item, idContains: "TKEY", commonKey: "initialkey") {
            if let value = await loadString(item)?.trimmingCharacters(in: .whitespaces),
               !value.isEmpty {
                return KeyNormalizer.toCamelot(value) ?? value
            }
        }
        return nil
    }

    static func artist(_ items: [AVMetadataItem]) async -> String? {
        for item in items where item.commonKey == .commonKeyArtist {
            if let value = await loadString(item)?.trimmingCharacters(in: .whitespaces),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /**
     * Approximate bitrate in kbps. Tries AVAssetTrack.estimatedDataRate first,
     * falls back to file size ÷ duration for VBR mp3s where AVFoundation reports 0.
     * Pass a pre-loaded duration to avoid re-loading the asset.
     */
    static func bitrateKbps(_ asset: AVURLAsset, knownDuration: Double) async -> Int? {
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if let track = tracks.first {
            let bps = (try? await track.load(.estimatedDataRate)) ?? 0
            if bps > 0 { return Int((bps / 1000).rounded()) }
        }
        // Fallback: file size in bytes × 8 / duration in seconds, in kbps
        guard knownDuration > 0 else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: asset.url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        let bps = Double(size.intValue) * 8.0 / knownDuration
        guard bps > 0 else { return nil }
        return Int((bps / 1000).rounded())
    }

    private static func loadString(_ item: AVMetadataItem) async -> String? {
        guard let result = try? await item.load(.stringValue) else { return nil }
        return result
    }

    private static func loadNumber(_ item: AVMetadataItem) async -> NSNumber? {
        guard let result = try? await item.load(.numberValue) else { return nil }
        return result
    }

    private static func matches(_ item: AVMetadataItem, idContains: String, commonKey: String) -> Bool {
        let id = item.identifier?.rawValue ?? ""
        if id.contains(idContains) { return true }
        if id.lowercased().contains(commonKey.lowercased()) { return true }
        if item.commonKey?.rawValue == commonKey { return true }
        return false
    }
}
