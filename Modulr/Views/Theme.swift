import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(nsColor: .controlAccentColor)

    static let folder     = Color(red: 0x3b/255, green: 0x8b/255, blue: 0xff/255)
    static let playlist   = Color(red: 0x2b/255, green: 0xd4/255, blue: 0x6a/255)
    static let favourites = Color(red: 0xff/255, green: 0x3b/255, blue: 0x3b/255)
    static let keyMatch   = Color(red: 0x2b/255, green: 0xd4/255, blue: 0x6a/255)

    static func color(for source: LibrarySource) -> Color {
        switch source {
        case .folder:     return folder
        case .playlist:   return playlist
        case .favourites: return favourites
        }
    }
}
