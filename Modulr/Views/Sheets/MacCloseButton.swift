import SwiftUI

/**
 * MacCloseButton
 * Apple traffic-light style red dot used in every modal so closing a sheet
 * matches the native window-close affordance. Sits top-left, ~12pt diameter,
 * reveals an xmark glyph on hover. `.keyboardShortcut(.cancelAction)` keeps
 * ESC working.
 */
struct MacCloseButton: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.37, blue: 0.36))
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                    )
                if hovering {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.trailing, 16)
        .onHover { hovering = $0 }
        .keyboardShortcut(.cancelAction)
        .help("Close")
    }
}
