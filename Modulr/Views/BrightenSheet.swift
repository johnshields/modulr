import SwiftUI
import AppKit

/**
 * BrightenSheet
 * Runs an ffmpeg harmonic exciter + high-shelf on a track, writing a `_bright`
 * sibling next to the source. User previews, scores quality, then either
 * replaces the original (trash the dull one + rename bright) or keeps both.
 *
 * NOTE: This cannot restore information lost to lossy compression — it just
 * fakes more "air" via synthesised harmonics. Use on MUDDY / COOKED sources;
 * already CRISP tracks tend to get harsh.
 */
struct BrightenSheet: View {
    let track: Track
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var quality: QualityCache
    @Environment(\.dismiss) private var dismiss

    @State private var phase: EnhancementPhase = .preview
    @State private var errorMessage: String?
    @State private var showSpectrum = false

    private var sourceURL: URL { track.url }
    private var targetURL: URL { sourceURL.sibling(suffix: "_bright") }
    private var targetExists: Bool {
        phase == .preview && FileManager.default.fileExists(atPath: targetURL.path)
    }
    private var brightVerdict: QualityVerdict? {
        guard phase == .done else { return nil }
        return quality.verdict(for: targetURL)
    }
    private var originalVerdict: QualityVerdict? { quality.verdict(for: sourceURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            } else if targetExists {
                Text("A _bright sibling already exists.")
                    .font(.caption).foregroundStyle(.yellow)
            }

            if phase == .done { verdictPanel }

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
            MacCloseButton(action: closeFromX)
        }
        .onChange(of: phase) { _, new in
            if new == .done { quality.requestVerdict(targetURL) }
        }
        .sheet(isPresented: $showSpectrum) {
            SpectrumSheet(trackURL: targetURL)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            switch phase {
            case .preview:
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.accent)
                titleColumn("Brighten Track?", sourceURL.lastPathComponent)
            case .working:
                ProgressView().controlSize(.regular).frame(width: 22, height: 22)
                titleColumn("Brightening…", sourceURL.lastPathComponent)
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                titleColumn("Brighten Complete", targetURL.lastPathComponent)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.red)
                titleColumn("Brighten Failed", sourceURL.lastPathComponent)
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
            if let orig = originalVerdict {
                HStack(spacing: 6) {
                    Text("Current:").font(.caption).foregroundStyle(.secondary)
                    Text(orig.label.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(orig.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            PrimaryButton(title: "Brighten Track", systemImage: "sparkles",
                          action: startBrighten, disabled: targetExists)
        }
    }

    private var workingBody: some View {
        Text("Running aexciter + high-shelf via ffmpeg…")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private var doneButtons: some View {
        Group {
            PrimaryButton(title: "Replace Original with Brightened",
                          systemImage: "arrow.triangle.2.circlepath",
                          action: replaceOriginal)
            SecondaryButton(title: "Preview Brightened",
                            systemImage: "play.circle", action: previewBright)
            SecondaryButton(title: "Show Spectrum", systemImage: "waveform.path") {
                showSpectrum = true
            }
            SecondaryButton(title: "Show in Finder",
                            systemImage: "folder", action: revealBright)
            KeepBothButton(action: finishAndDismiss)
        }
    }

    private enum Recommendation {
        case replace, discard, neutral

        var label: String {
            switch self {
            case .replace: return "Recommended: Replace Original"
            case .discard: return "Recommended: Discard Brightened"
            case .neutral: return "No clear improvement"
            }
        }
        var icon: String {
            switch self {
            case .replace: return "checkmark.seal.fill"
            case .discard: return "exclamationmark.triangle.fill"
            case .neutral: return "questionmark.circle"
            }
        }
        var tint: Color {
            switch self {
            case .replace: return .green
            case .discard: return .red
            case .neutral: return .yellow
            }
        }
    }

    private var recommendation: Recommendation {
        guard let orig = originalVerdict, let bright = brightVerdict,
              orig.rank >= 0, bright.rank >= 0
        else { return .neutral }
        if bright.rank > orig.rank { return .replace }
        if bright.rank < orig.rank { return .discard }
        return .neutral
    }

    @ViewBuilder
    private var verdictPanel: some View {
        if let v = brightVerdict {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let orig = originalVerdict {
                        Text(orig.label.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(orig.color)
                        Image(systemName: "arrow.right")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(v.label.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(v.color)
                    Spacer()
                }
                Text(v.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: recommendation.icon)
                        .foregroundStyle(recommendation.tint)
                    Text(recommendation.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(recommendation.tint)
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scoring brightened version…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func startBrighten() {
        phase = .working
        errorMessage = nil
        let target = targetURL
        analyzer.brightenFile(sourceURL) {
            DispatchQueue.main.async {
                guard FileManager.default.fileExists(atPath: target.path) else {
                    errorMessage = "Brighten failed. Check Console for ffmpeg output."
                    phase = .error
                    return
                }
                phase = .done
            }
        }
    }

    private func previewBright() {
        player.load(targetURL)
        player.play()
    }

    private func revealBright() {
        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
    }

    /// Trash the original then rename the _bright sibling onto its path so the
    /// rest of the library (Rekordbox links, recents, playlists) keeps pointing
    /// at the same filename — but with brighter audio.
    private func replaceOriginal() {
        let source = sourceURL
        let bright = targetURL
        do {
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
            try FileManager.default.moveItem(at: bright, to: source)
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
