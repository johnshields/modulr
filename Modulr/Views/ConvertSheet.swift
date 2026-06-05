import SwiftUI
import AppKit

/**
 * ConvertSheet
 * Two-step modal styled like DeleteSheet for wav/m4a -> 320 kbps MP3:
 *   1. Confirm + run ffmpeg.
 *   2. After success, preview the new MP3 then decide what happens to the
 *      original (move to Trash or keep both).
 */
struct ConvertSheet: View {
    let track: Track
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var quality: QualityCache
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case preview, converting, converted, error }

    @State private var phase: Phase = .preview
    @State private var errorMessage: String?
    @State private var showSpectrum = false

    private static let accent = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)

    private var sourceURL: URL { track.url }
    private var targetURL: URL {
        track.url.deletingPathExtension().appendingPathExtension("mp3")
    }
    private var targetExists: Bool {
        phase == .preview &&
        FileManager.default.fileExists(atPath: targetURL.path)
    }

    private var convertedVerdict: QualityVerdict? {
        guard phase == .converted else { return nil }
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

            if phase == .converted { verdictPanel }

            Divider()

            VStack(spacing: 8) {
                switch phase {
                case .preview:    previewButtons
                case .converting: convertingBody
                case .converted:  convertedButtons
                case .error:      errorButtons
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .overlay(alignment: .topTrailing) {
            MacCloseButton(action: closeFromX)
        }
        .onChange(of: phase) { _, new in
            if new == .converted { quality.requestVerdict(targetURL) }
        }
        .sheet(isPresented: $showSpectrum) {
            SpectrumSheet(trackURL: targetURL)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            switch phase {
            case .preview:
                Image(systemName: "waveform.path.badge.plus")
                    .font(.title2).foregroundStyle(Self.accent)
                titleColumn(title: "Convert to MP3?", subtitle: sourceURL.lastPathComponent)
            case .converting:
                ProgressView().controlSize(.regular)
                    .frame(width: 22, height: 22)
                titleColumn(title: "Converting…", subtitle: sourceURL.lastPathComponent)
            case .converted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
                titleColumn(title: "Conversion Complete",
                            subtitle: targetURL.lastPathComponent)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2).foregroundStyle(.red)
                titleColumn(title: "Convert Failed", subtitle: sourceURL.lastPathComponent)
            }
        }
    }

    private func titleColumn(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: - Phase bodies

    private var previewButtons: some View {
        Button(action: startConvert) {
            Label("Convert to MP3", systemImage: "waveform.path.badge.plus")
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Self.accent)
        .disabled(targetExists)
    }

    private var convertingBody: some View {
        Text("Transcoding via ffmpeg…")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private var convertedButtons: some View {
        Group {
            Button(action: trashOriginalAndClose) {
                Label("Move Original to Trash", systemImage: "trash")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.accent)

            Button(action: previewInModulr) {
                Label("Preview MP3", systemImage: "play.circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Button { showSpectrum = true } label: {
                Label("Show Spectrum", systemImage: "waveform.path")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Button(action: revealInFinder) {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Button("Keep Both", action: keepBothAndClose)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
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

    private var errorButtons: some View {
        Button {
            phase = .preview
            errorMessage = nil
        } label: {
            Label("Retry", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Self.accent)
    }

    // MARK: - Actions

    private func startConvert() {
        phase = .converting
        errorMessage = nil
        let source = sourceURL
        let target = targetURL
        analyzer.convertToMP3(source) {
            DispatchQueue.main.async {
                guard FileManager.default.fileExists(atPath: target.path) else {
                    errorMessage = "Convert failed. Check Console for ffmpeg output."
                    phase = .error
                    return
                }
                phase = .converted
            }
        }
    }

    private func previewInModulr() {
        player.load(targetURL)
        player.play()
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
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
        case .preview:    dismiss()
        case .converting: cancelRunning()
        case .converted:  discardAndClose()
        case .error:      dismiss()
        }
    }
}
