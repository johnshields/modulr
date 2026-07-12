import SwiftUI

/**
 * SheetControls
 * Reusable title header and button styles shared across the modals, keeping
 * primary, secondary and destructive actions consistent.
 */

@ViewBuilder
func sheetTitle(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
}

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
