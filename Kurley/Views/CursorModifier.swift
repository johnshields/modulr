import SwiftUI
import AppKit

/**
 * Cursor modifier
 * SwiftUI on macOS does not change the cursor for buttons or draggable rows.
 * This modifier pushes/pops an NSCursor while the mouse is inside the view.
 */
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
