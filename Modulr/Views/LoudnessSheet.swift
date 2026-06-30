import SwiftUI
import AppKit

/**
 * LoudnessSheet
 * Measures peak via ffmpeg, computes a safe-headroom boost, and writes a
 * `<stem>_loud` sibling. User previews, then either replaces the original
 * (trash + rename) or keeps both. Shares state and buttons with BrightenSheet
 * via EnhancementPhase + Primary/Secondary button views.
 */
struct LoudnessSheet: View {
    let track: Track
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var quality: QualityCache
    @Environment(\.dismiss) private var dismiss

    @State private var phase: EnhancementPhase = .preview
    @State private var errorMessage: String?
    @State private var gainSummary: String?

    private var sourceURL: URL { track.url }
    private var targetURL: URL { sourceURL.sibling(suffix: "_loud") }
    private var lifecycle: SheetLifecycle {
        .init(library: library, analyzer: analyzer, targetURL: targetURL, dismiss: dismiss)
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
                case .error:   RetryButton { phase = .preview; errorMessage = nil }
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .overlay(alignment: .topTrailing) {
            MacCloseButton { lifecycle.closeFromX(phase: phase) }
        }
        .task { library.reloadCurrent() }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            switch phase {
            case .preview:
                Image(systemName: "speaker.wave.3.fill")
                    .font(.title2).foregroundStyle(Theme.accent)
                sheetTitle("Normalise Loudness?", sourceURL.lastPathComponent)
            case .working:
                ProgressView().controlSize(.regular).frame(width: 22, height: 22)
                sheetTitle("Boosting…", sourceURL.lastPathComponent)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
                sheetTitle("Boost Complete", targetURL.lastPathComponent)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2).foregroundStyle(.red)
                sheetTitle("Boost Failed", sourceURL.lastPathComponent)
            }
        }
    }


    private var previewButtons: some View {
        Group {
            Text("Lifts peak to ~ -0.3 dBFS without clipping.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

            PrimaryButton(title: "Boost to Safe Peak",
                          systemImage: "speaker.wave.3.fill",
                          action: startBoost, disabled: targetExists)
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
            KeepBothButton(action: { lifecycle.finish() })
            DestructiveButton(title: "Replace Original with Boosted",
                              systemImage: "arrow.triangle.2.circlepath",
                              action: replaceOriginal)
            SecondaryButton(title: "Preview Boosted",
                            systemImage: "play.circle", action: previewBoosted)
        }
    }

    // MARK: - Actions

    private func startBoost() {
        library.reloadCurrent()
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            errorMessage = "Source file is no longer at \(sourceURL.lastPathComponent). Refresh and try again."
            phase = .error
            return
        }
        phase = .working
        errorMessage = nil
        let target = targetURL
        analyzer.boostFileSibling(sourceURL) {
            DispatchQueue.main.async {
                let boostedLine = analyzer.log.last(where: { $0.hasPrefix("BOOSTED:") })
                if FileManager.default.fileExists(atPath: target.path) {
                    gainSummary = boostedLine?
                        .replacingOccurrences(of: "BOOSTED:", with: "Gain applied:")
                    phase = .done
                    return
                }
                if analyzer.log.contains(where: { $0.contains("already loud") }) {
                    errorMessage = "Track is already near peak — no boost applied."
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
        lifecycle.finish()
    }
}
