import Foundation

struct Track: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var title: String
    var duration: TimeInterval
    var tags: [String] = []

    var fileType: String { url.pathExtension.uppercased() }
}
