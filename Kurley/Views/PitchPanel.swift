import SwiftUI

/**
 * PitchPanel
 * Read-only chip in transport row showing the current track's BPM and key.
 */
struct PitchPanel: View {
    @ObservedObject var player: AudioPlayer
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyzeSheet: Bool

    private var currentTrack: Track? {
        guard let url = player.currentURL else { return nil }
        return library.tracks.first(where: { $0.url == url })
    }

    private var summary: String {
        guard let t = currentTrack else { return "—" }
        var parts: [String] = []
        if let b = t.bpm { parts.append("\(b) BPM") }
        if let k = t.key { parts.append(KeyNormalizer.toMusical(k)) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var body: some View {
        Label(summary, systemImage: "metronome")
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)
            .help("Track BPM and key — \(summary)")
    }
}
