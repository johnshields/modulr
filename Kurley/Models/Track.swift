import Foundation

struct Track: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var title: String
    var artist: String?
    var duration: TimeInterval
    var bpm: Int?
    var key: String?
    var tags: [String] = []

    var fileType: String { url.pathExtension.uppercased() }
    var bpmSort: Int { bpm ?? 0 }
    var bpmDisplay: String { bpm.map(String.init) ?? "—" }
    var keyDisplay: String {
        guard let k = key else { return "—" }
        return KeyNormalizer.toMusical(k)
    }
    var keySort: String { key ?? "" }
    var artistDisplay: String { artist ?? "—" }
    var artistSort: String { artist ?? "" }
}
