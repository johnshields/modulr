import Foundation
import AppKit

/**
 * ArtworkFinder
 * Searches iTunes Search API for matching tracks and returns artwork candidates.
 */
struct ArtworkCandidate: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let collection: String
    let thumbURL: URL
    let highResURL: URL
}

enum ArtworkFinder {
    /// Edition / remix words dropped from the title.
    private static let noise: Set<String> = [
        "remix", "mix", "edit", "dub", "extended", "original", "radio", "club",
        "vip", "bootleg", "rework", "version", "flip", "refix", "remake",
        "instrumental", "remastered", "feat", "ft", "featuring",
    ]

    /// Query iTunes, trying progressively looser terms until one returns results.
    static func search(title: String, artist: String?) async -> [ArtworkCandidate] {
        let words = looseWords(title)
        let primary = primaryArtist(artist)

        var terms: [String] = []
        func add(_ parts: [String]) {
            let t = parts.filter { !$0.isEmpty }.joined(separator: " ")
            if !t.isEmpty && !terms.contains(t) { terms.append(t) }
        }
        add([words.joined(separator: " "), primary])
        add([words.joined(separator: " ")])
        add([words.prefix(2).joined(separator: " "), primary])
        add([words.first ?? "", primary])
        add([primary])

        for term in terms {
            let results = await query(term)
            if !results.isEmpty { return results }
        }
        return []
    }

    private static func query(_ term: String) async -> [ArtworkCandidate] {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=12&term=\(encoded)")
        else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return [] }

            return results.compactMap { item in
                guard let trackName = item["trackName"] as? String,
                      let artistName = item["artistName"] as? String,
                      let artwork = item["artworkUrl100"] as? String,
                      let thumbURL = URL(string: artwork) else { return nil }
                let collection = item["collectionName"] as? String ?? ""
                let highRes = artwork.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")
                return ArtworkCandidate(
                    title: trackName,
                    artist: artistName,
                    collection: collection,
                    thumbURL: thumbURL,
                    highResURL: URL(string: highRes) ?? thumbURL
                )
            }
        } catch {
            return []
        }
    }

    /// Title split into lowercase words with punctuation and edition noise removed.
    private static func looseWords(_ title: String) -> [String] {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !noise.contains($0) }
    }

    /// First credited artist only (before a comma, ampersand or "feat").
    private static func primaryArtist(_ artist: String?) -> String {
        guard let artist else { return "" }
        return artist
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?
            .replacingOccurrences(of: "(?i)\\b(feat|ft|featuring)\\b.*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /**
     * Download artwork data from URL.
     */
    static func download(_ url: URL) async -> Data? {
        try? await URLSession.shared.data(from: url).0
    }
}
