import Foundation

/**
 * UID
 * Prefixed unique id for DB rows: PREFIX_ + 6 uppercase hex, e.g. PLST_A1B2C3.
 */
enum UID {
    static func gen(_ prefix: String) -> String {
        let hex = (0..<4).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined()
        return "\(prefix)_\(hex.prefix(6))"
    }
}
