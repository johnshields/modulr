import Foundation
import AVFoundation

/**
 * MetadataReader
 * Pulls common metadata fields out of AVURLAsset
 */
enum MetadataReader {
    static func bpm(_ asset: AVURLAsset) -> Int? {
        for item in asset.metadata where matches(item, idContains: "TBPM", commonKey: "beatsPerMinute") {
            if let n = item.numberValue?.intValue { return n }
            if let s = item.stringValue, let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
        }
        return nil
    }

    static func key(_ asset: AVURLAsset) -> String? {
        for item in asset.metadata where matches(item, idContains: "TKEY", commonKey: "initialkey") {
            if let s = item.stringValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                return KeyNormalizer.toCamelot(s) ?? s
            }
        }
        return nil
    }

    /**
     * Approximate bitrate in kbps. Tries AVAssetTrack.estimatedDataRate first,
     * falls back to file size ÷ duration for VBR mp3s where AVFoundation reports 0.
     */
    static func bitrateKbps(_ asset: AVURLAsset) -> Int? {
        if let track = asset.tracks(withMediaType: .audio).first {
            let bps = track.estimatedDataRate
            if bps > 0 { return Int((bps / 1000).rounded()) }
        }
        // Fallback: file size in bytes × 8 / duration in seconds, in kbps
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration > 0 else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: asset.url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        let bps = Double(size.intValue) * 8.0 / duration
        guard bps > 0 else { return nil }
        return Int((bps / 1000).rounded())
    }

    static func artist(_ asset: AVURLAsset) -> String? {
        for item in asset.metadata where item.commonKey == .commonKeyArtist {
            if let s = item.stringValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    private static func matches(_ item: AVMetadataItem, idContains: String, commonKey: String) -> Bool {
        let id = item.identifier?.rawValue ?? ""
        if id.contains(idContains) { return true }
        if id.lowercased().contains(commonKey.lowercased()) { return true }
        if item.commonKey?.rawValue == commonKey { return true }
        return false
    }
}
