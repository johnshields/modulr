import SwiftUI

/**
 * EnhancementPhase
 * Shared finite-state-machine ConvertSheet / BrightenSheet / LoudnessSheet all
 * walk: preview the action -> ffmpeg working -> done with verdict -> error.
 */
enum EnhancementPhase { case preview, working, done, error }

/**
 * Reusable button styles for the enhancement modals, keeping primary and
 * secondary actions consistent across Convert / Brighten / Loudness.
 */
struct PrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(disabled)
    }
}

struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }
}

struct KeepBothButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Keep Both", systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }
}

struct DestructiveButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}

struct RetryButton: View {
    let action: () -> Void

    var body: some View {
        PrimaryButton(title: "Retry", systemImage: "arrow.clockwise", action: action)
    }
}
