import Foundation

struct Track: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var title: String
    var artist: String?
    var duration: TimeInterval
    var bpm: Int?
    var key: String?
    var bitrate: Int?
    var tags: [String] = []

    var fileType: String { url.pathExtension.uppercased() }
    var typeAndBitrate: String {
        guard let kbps = bitrate else { return fileType }
        return "\(fileType) · \(kbps)"
    }
    var bitrateDisplay: String {
        bitrate.map { "\($0) kbps" } ?? "—"
    }
    var bpmSort: Int { bpm ?? 0 }
    var bpmDisplay: String { bpm.map(String.init) ?? "—" }
    var keyDisplay: String {
        guard let k = key else { return "—" }
        return KeyNormalizer.toMusical(k)
    }
    var keySort: String { key ?? "" }
    var artistDisplay: String { artist ?? "—" }
    var artistSort: String { artist ?? "" }

    /**
     * Returns a copy of self with selected fields replaced. Preserves id.
     */
    func with(
        url: URL? = nil,
        title: String? = nil,
        artist: String?? = nil,
        duration: TimeInterval? = nil,
        bpm: Int?? = nil,
        key: String?? = nil
    ) -> Track {
        var copy = self
        if let url { copy.url = url }
        if let title { copy.title = title }
        if case let .some(value) = artist { copy.artist = value }
        if let duration { copy.duration = duration }
        if case let .some(value) = bpm { copy.bpm = value }
        if case let .some(value) = key { copy.key = value }
        return copy
    }
}
