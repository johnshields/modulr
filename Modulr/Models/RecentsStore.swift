import Foundation

/**
 * RecentsStore
 * UserDefaults-backed store for last opened folder and recents list
 */
final class RecentsStore {
    private let defaults = UserDefaults.standard
    private let kLastFolder = "kurley.lastFolder"
    private let kRecents = "kurley.recents"
    private let maxRecents = 10

    var lastFolder: URL? {
        guard let path = defaults.string(forKey: kLastFolder) else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func setLastFolder(_ url: URL) {
        defaults.set(url.path, forKey: kLastFolder)
    }

    func loadRecents() -> [URL] {
        let paths = defaults.stringArray(forKey: kRecents) ?? []
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func addRecent(_ url: URL, current: [URL]) -> [URL] {
        var list = current.filter { $0 != url }
        list.insert(url, at: 0)
        if list.count > maxRecents { list = Array(list.prefix(maxRecents)) }
        defaults.set(list.map(\.path), forKey: kRecents)
        return list
    }
}
