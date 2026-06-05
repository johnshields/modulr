import SwiftUI
import AppKit

/**
 * ConvertSheet
 * Two-step modal styled like DeleteSheet for wav/m4a -> 320 kbps MP3:
 *   1. Confirm + run ffmpeg.
 *   2. After success, preview the new MP3 then decide what happens to the
 *      original (move to Trash or keep both).
 * Shares EnhancementPhase / Primary+Secondary button views with Brighten +
 * Loudness so the three modals feel like one family.
 */
struct ConvertSheet: View {
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
    private var targetURL: URL { sourceURL.changingExtension(to: "mp3") }
    private var targetExists: Bool {
        phase == .preview && FileManager.default.fileExists(atPath: targetURL.path)
    }
    private var convertedVerdict: QualityVerdict? {
        guard phase == .done else { return nil }
        return quality.verdict(for: targetURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let err = errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            } else if targetExists {
                Text("An MP3 with this name already exists.")
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
        .task { refreshFolder() }
        .sheet(isPresented: $showSpectrum) {
            SpectrumSheet(trackURL: targetURL)
        }
    }

    private func refreshFolder() {
        guard let folder = library.currentFolder else { return }
        library.openFolder(folder)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            switch phase {
            case .preview:
                Image(systemName: "waveform.path.badge.plus")
                    .font(.title2).foregroundStyle(Theme.accent)
                titleColumn("Convert to MP3?", sourceURL.lastPathComponent)
            case .working:
                ProgressView().controlSize(.regular).frame(width: 22, height: 22)
                titleColumn("Converting…", sourceURL.lastPathComponent)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
                titleColumn("Conversion Complete", targetURL.lastPathComponent)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2).foregroundStyle(.red)
                titleColumn("Convert Failed", sourceURL.lastPathComponent)
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
        PrimaryButton(title: "Convert to MP3",
                      systemImage: "waveform.path.badge.plus",
                      action: startConvert, disabled: targetExists)
    }

    private var workingBody: some View {
        Text("Transcoding via ffmpeg…")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private var doneButtons: some View {
        Group {
            KeepBothButton(action: keepBothAndClose)
            DestructiveButton(title: "Move Original to Trash",
                              systemImage: "trash",
                              action: trashOriginalAndClose)
            SecondaryButton(title: "Preview MP3", systemImage: "play.circle",
                            action: previewInModulr)
            SecondaryButton(title: "Show Spectrum", systemImage: "waveform.path") {
                showSpectrum = true
            }
        }
    }

    @ViewBuilder
    private var verdictPanel: some View {
        if let v = convertedVerdict {
            HStack(spacing: 8) {
                Text(v.label.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(v.color)
                Text(v.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scoring quality of new MP3…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func startConvert() {
        refreshFolder()
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            errorMessage = "Source file is no longer at \(sourceURL.lastPathComponent). Refresh and try again."
            phase = .error
            return
        }
        phase = .working
        errorMessage = nil
        let target = targetURL
        analyzer.convertToMP3(sourceURL) {
            DispatchQueue.main.async {
                guard FileManager.default.fileExists(atPath: target.path) else {
                    errorMessage = "Convert failed. Check Console for ffmpeg output."
                    phase = .error
                    return
                }
                phase = .done
            }
        }
    }

    private func previewInModulr() {
        player.load(targetURL)
        player.play()
    }

private func trashOriginalAndClose() {
        do {
            try FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)
        } catch {
            errorMessage = "MP3 kept but Trash move failed: \(error.localizedDescription)"
            phase = .error
            return
        }
        finishAndDismiss()
    }

    private func keepBothAndClose() { finishAndDismiss() }

    private func discardAndClose() {
        try? FileManager.default.removeItem(at: targetURL)
        finishAndDismiss()
    }

    private func cancelRunning() {
        analyzer.cancel()
        try? FileManager.default.removeItem(at: targetURL)
        dismiss()
    }

    private func finishAndDismiss() {
        if let folder = library.currentFolder { library.openFolder(folder) }
        dismiss()
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
