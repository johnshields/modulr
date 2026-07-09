import Foundation
import CryptoKit

struct Track: Identifiable, Hashable {
    var url: URL

    /// Stable, URL-derived identity so reloads diff rows in place.
    var id: UUID {
        let digest = Insecure.MD5.hash(data: Data(url.absoluteString.utf8))
        return digest.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }
    var title: String
    var artist: String?
    var duration: TimeInterval
    var bpm: Int?
    var key: String?
    var bitrate: Int?
    var trackNumber: Int?
    var dateAdded: Date?
    var tags: [String] = []

    var dateAddedSort: Date { dateAdded ?? .distantPast }
    var dateAddedDisplay: String {
        guard let date = dateAdded else { return "" }
        let fmt = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? Self.thisYearFmt : Self.oldYearFmt
        return fmt.string(from: date)
    }
    private static let thisYearFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"; return f
    }()
    private static let oldYearFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f
    }()

    var trackNumberSort: Int { trackNumber ?? Int.max }
    var trackNumberDisplay: String { trackNumber.map(String.init) ?? "" }

    /// True when the filename already ends with the DJ-format `_KEY_BPM` suffix.
    var isDJFormatted: Bool {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.range(of: #"_[A-G][#b]?m?_\d{2,3}$"#, options: .regularExpression) != nil
    }

    var fileType: String { url.pathExtension.uppercased() }
    var typeAndBitrate: String {
        guard let kbps = bitrate else { return fileType }
        return "\(fileType) · \(kbps)"
    }
    var bitrateDisplay: String {
        bitrate.map { "\($0) kbps" } ?? ""
    }
    var bpmSort: Int { bpm ?? 0 }
    var bpmDisplay: String { bpm.map(String.init) ?? "" }
    var keyDisplay: String {
        guard let k = key else { return "" }
        return KeyNormalizer.toMusical(k)
    }
    var keySort: String { key ?? "" }
    var artistDisplay: String { artist ?? "" }
    var artistSort: String { artist ?? "" }

    func with(
        url: URL? = nil,
        title: String? = nil,
        artist: String?? = nil,
        duration: TimeInterval? = nil,
        bpm: Int?? = nil,
        key: String?? = nil,
        trackNumber: Int?? = nil,
        dateAdded: Date?? = nil
    ) -> Track {
        var copy = self
        if let url { copy.url = url }
        if let title { copy.title = title }
        if case let .some(value) = artist { copy.artist = value }
        if let duration { copy.duration = duration }
        if case let .some(value) = bpm { copy.bpm = value }
        if case let .some(value) = key { copy.key = value }
        if case let .some(value) = trackNumber { copy.trackNumber = value }
        if case let .some(value) = dateAdded { copy.dateAdded = value }
        return copy
    }
}
