import Foundation

/**
 * KeyNormalizer
 * Convert musical notation (e.g. "Emaj", "F#m", "Bb minor") to Camelot ("4B", "11A", "8A")
 */
enum KeyNormalizer {
    private static let pitchMap: [String: Int] = [
        "C": 0, "C#": 1, "DB": 1, "D": 2, "D#": 3, "EB": 3,
        "E": 4, "FB": 4, "F": 5, "E#": 5, "F#": 6, "GB": 6,
        "G": 7, "G#": 8, "AB": 8, "A": 9, "A#": 10, "BB": 10,
        "B": 11, "CB": 11
    ]

    private static let camelot: [String: String] = [
        "0_1":"8B","0_0":"5A","1_1":"3B","1_0":"12A",
        "2_1":"10B","2_0":"7A","3_1":"5B","3_0":"2A",
        "4_1":"12B","4_0":"9A","5_1":"7B","5_0":"4A",
        "6_1":"2B","6_0":"11A","7_1":"9B","7_0":"6A",
        "8_1":"4B","8_0":"1A","9_1":"11B","9_0":"8A",
        "10_1":"6B","10_0":"3A","11_1":"1B","11_0":"10A"
    ]

    private static let camelotToMusical: [String: String] = [
        "1A":"Abm","1B":"B",   "2A":"Ebm","2B":"F#",
        "3A":"Bbm","3B":"Db",  "4A":"Fm", "4B":"Ab",
        "5A":"Cm", "5B":"Eb",  "6A":"Gm", "6B":"Bb",
        "7A":"Dm", "7B":"F",   "8A":"Am", "8B":"C",
        "9A":"Em", "9B":"G",   "10A":"Bm","10B":"D",
        "11A":"F#m","11B":"A", "12A":"C#m","12B":"E"
    ]

    /**
     * Camelot → musical notation (e.g. "4B" → "Ab", "10A" → "Bm")
     */
    static func toMusical(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return camelotToMusical[s] ?? raw
    }

    static func toCamelot(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !s.isEmpty else { return nil }

        if isCamelot(s) { return s }

        var pitch = ""
        var rest = s
        if rest.count >= 2, ["#", "B"].contains(String(rest[rest.index(after: rest.startIndex)])) && rest.first?.isLetter == true {
            pitch = String(rest.prefix(2))
            rest = String(rest.dropFirst(2))
        } else if let first = rest.first, first.isLetter {
            pitch = String(first)
            rest = String(rest.dropFirst())
        }

        guard let p = pitchMap[pitch] else { return nil }

        rest = rest.replacingOccurrences(of: " ", with: "")
        let isMinor = rest.hasPrefix("MIN") || rest == "M" || rest.hasPrefix("MOLL") || rest == "MIN"
        let isMajor = rest.hasPrefix("MAJ") || rest.isEmpty || rest == "DUR"
        let mode = isMinor ? 0 : (isMajor ? 1 : 1)

        return camelot["\(p)_\(mode)"]
    }

    private static func isCamelot(_ s: String) -> Bool {
        guard s.count >= 2, s.count <= 3 else { return false }
        let last = s.last
        guard last == "A" || last == "B" else { return false }
        let num = s.dropLast()
        guard let n = Int(num), n >= 1 && n <= 12 else { return false }
        return true
    }
}
