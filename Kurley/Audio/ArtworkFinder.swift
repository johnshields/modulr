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
    /**
     * Query iTunes Search API. Returns up to 12 candidates ordered by relevance.
     */
    static func search(title: String, artist: String?) async -> [ArtworkCandidate] {
        let term = [title, artist ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty,
              let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
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

    /**
     * Download artwork data from URL.
     */
    static func download(_ url: URL) async -> Data? {
        try? await URLSession.shared.data(from: url).0
    }
}
