import SwiftUI
import AppKit

/**
 * LoudnessSheet
 * Measures peak via ffmpeg, computes a safe-headroom boost, and writes a
 * `<stem>_loud` sibling. User previews, then either replaces the original
 * (trash + rename) or keeps both. Mirrors BrightenSheet exactly so the
 * enhancement modals feel like one feature family.
 */
struct LoudnessSheet: View {
    let track: Track
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var quality: QualityCache
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case preview, working, done, error }

    @State private var phase: Phase = .preview
    @State private var errorMessage: String?
    @State private var gainSummary: String?

    private static let accent = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)

    private var sourceURL: URL { track.url }
    private var targetURL: URL {
        let dir = sourceURL.deletingLastPathComponent()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem)_loud")
            .appendingPathExtension(sourceURL.pathExtension)
    }
    private var targetExists: Bool {
        phase == .preview && FileManager.default.fileExists(atPath: targetURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            } else if targetExists {
                Text("A _loud sibling already exists.")
                    .font(.caption).foregroundStyle(.yellow)
            }

            if let summary = gainSummary, phase == .done {
                Text(summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                switch phase {
                case .preview: previewButtons
                case .working: workingBody
                case .done:    doneButtons
                case .error:   errorButtons
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .overlay(alignment: .topTrailing) {
            MacCloseButton(action: closeFromX)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            switch phase {
            case .preview:
                Image(systemName: "speaker.wave.3.fill")
                    .font(.title2).foregroundStyle(Self.accent)
                titleColumn("Normalise Loudness?", sourceURL.lastPathComponent)
            case .working:
                ProgressView().controlSize(.regular).frame(width: 22, height: 22)
                titleColumn("Boosting…", sourceURL.lastPathComponent)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
                titleColumn("Boost Complete", targetURL.lastPathComponent)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2).foregroundStyle(.red)
                titleColumn("Boost Failed", sourceURL.lastPathComponent)
            }
        }
    }

    private func titleColumn(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var previewButtons: some View {
        Group {
            Text("Lifts peak to ~ -0.3 dBFS without clipping.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

            Button(action: startBoost) {
                Label("Boost to Safe Peak", systemImage: "speaker.wave.3.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.accent)
            .disabled(targetExists)
        }
    }

    private var workingBody: some View {
        Text("Measuring + applying gain via ffmpeg…")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private var doneButtons: some View {
        Group {
            Button(action: replaceOriginal) {
                Label("Replace Original with Boosted", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.accent)

            Button(action: previewBoosted) {
                Label("Preview Boosted", systemImage: "play.circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Button(action: revealBoosted) {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Button("Keep Both", action: finishAndDismiss)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
    }

    private var errorButtons: some View {
        Button {
            phase = .preview; errorMessage = nil
        } label: {
            Label("Retry", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Self.accent)
    }

    // MARK: - Actions

    private func startBoost() {
        phase = .working
        errorMessage = nil
        let target = targetURL
        analyzer.boostFileSibling(sourceURL) {
            DispatchQueue.main.async {
                // Parse the analyzer log for the BOOSTED line so we can show
                // the user how much gain was added.
                let boostedLine = analyzer.log.last(where: { $0.hasPrefix("BOOSTED:") })
                if FileManager.default.fileExists(atPath: target.path) {
                    gainSummary = boostedLine?.replacingOccurrences(of: "BOOSTED:", with: "Gain applied:")
                    phase = .done
                    return
                }
                // No sibling produced — either already loud or measure failed.
                if let plan = analyzer.log.last(where: { $0.contains("already loud") }) {
                    errorMessage = "Track is already near peak — no boost applied."
                    _ = plan
                } else {
                    errorMessage = "Boost failed. Check Console for ffmpeg output."
                }
                phase = .error
            }
        }
    }

    private func previewBoosted() {
        player.load(targetURL)
        player.play()
    }

    private func revealBoosted() {
        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
    }

    private func replaceOriginal() {
        let source = sourceURL
        let boosted = targetURL
        do {
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
            try FileManager.default.moveItem(at: boosted, to: source)
        } catch {
            errorMessage = "Replace failed: \(error.localizedDescription)"
            phase = .error
            return
        }
        quality.invalidate(source)
        finishAndDismiss()
    }

    private func finishAndDismiss() {
        if let folder = library.currentFolder { library.openFolder(folder) }
        dismiss()
    }

    private func cancelRunning() {
        analyzer.cancel()
        try? FileManager.default.removeItem(at: targetURL)
        dismiss()
    }

    private func discardAndClose() {
        try? FileManager.default.removeItem(at: targetURL)
        finishAndDismiss()
    }

    private func closeFromX() {
        switch phase {
        case .preview: dismiss()
        case .working: cancelRunning()
        case .done:    discardAndClose()
        case .error:   dismiss()
        }
    }
}
