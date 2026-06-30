import SwiftUI

/**
 * EnhancementPhase
 * Shared finite-state-machine ConvertSheet / BrightenSheet / LoudnessSheet all
 * walk: preview the action -> ffmpeg working -> done with verdict -> error.
 */
enum EnhancementPhase { case preview, working, done, error }

/**
 * SheetLifecycle
 * Shared open/cancel/finish flow for the enhancement modals, which all reload
 * the folder on success and discard the in-progress sibling on cancel.
 */
struct SheetLifecycle {
    let library: Library
    let analyzer: Analyzer
    let targetURL: URL
    let dismiss: DismissAction

    func finish() {
        if let folder = library.currentFolder { library.openFolder(folder) }
        dismiss()
    }

    func cancel() {
        analyzer.cancel()
        try? FileManager.default.removeItem(at: targetURL)
        dismiss()
    }

    func discard() {
        try? FileManager.default.removeItem(at: targetURL)
        finish()
    }

    func closeFromX(phase: EnhancementPhase) {
        switch phase {
        case .preview, .error: dismiss()
        case .working: cancel()
        case .done: discard()
        }
    }
}

@ViewBuilder
func sheetTitle(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
}

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
