import SwiftUI
import AppKit

enum Theme {
    // Follow the user's macOS accent (System Settings > Appearance > Accent),
    // matching stock Apple apps. Resolves dynamically, including "multicolour".
    static let accent = Color(nsColor: .controlAccentColor)
}
