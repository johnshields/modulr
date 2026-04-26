import SwiftUI

/**
 * PitchPanel
 * Compact pill in transport row. Shows current vs original BPM/key.
 * Popover lets user type a target BPM or key — derives tempo/pitch internally.
 */
struct PitchPanel: View {
    @ObservedObject var player: AudioPlayer
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyzeSheet: Bool
    @State private var showPopover = false
    @State private var bpmText = ""
    @State private var keyText = ""

    private var currentTrack: Track? {
        guard let url = player.currentURL else { return nil }
        return library.tracks.first(where: { $0.url == url })
    }

    private var originalBPM: Int? { currentTrack?.bpm }
    private var originalKey: String? { currentTrack?.key }
    private var semitones: Int { Int(round(player.pitchCents / 100)) }

    /// Effective tempo rate the listener actually hears.
    /// In vinyl mode tempoRate and pitchCents are already kept in lockstep,
    /// so either one alone represents the full shift.
    private var effectiveRate: Float {
        player.tempoRate
    }

    /// Effective semitone shift the listener actually hears.
    private var effectiveSemitones: Int {
        if player.pitchMode == .vinyl {
            return Int(round(log2(Double(player.tempoRate)) * 12))
        }
        return semitones
    }

    private var tweakedBPM: Int? {
        guard let bpm = originalBPM else { return nil }
        return Int((Float(bpm) * effectiveRate).rounded())
    }

    private var tweakedKey: String? {
        guard let k = originalKey else { return nil }
        return KeyNormalizer.shift(k, by: effectiveSemitones).map(KeyNormalizer.toMusical)
            ?? KeyNormalizer.toMusical(k)
    }

    private var pillSummary: String {
        var parts: [String] = []
        if let b = tweakedBPM { parts.append("\(b) BPM") }
        else { parts.append(String(format: "%.2fx", player.tempoRate)) }
        if let k = tweakedKey { parts.append(k) }
        else if semitones != 0 { parts.append(formatSemitones(semitones)) }
        return parts.joined(separator: " · ")
    }

    private var isModified: Bool {
        player.tempoRate != 1.0 || player.pitchCents != 0
    }

    var body: some View {
        Button { showPopover.toggle() } label: {
            Label(pillSummary, systemImage: "metronome")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isModified ? Theme.accent.opacity(0.85) : Color.white.opacity(0.08))
        .cornerRadius(6)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tempo & Pitch").font(.headline)
                Spacer()
                Button("Reset") {
                    player.resetTempoAndPitch()
                    syncFields()
                }
                .disabled(!isModified)
                .controlSize(.small)
            }

            originalRow

            Divider()

            tempoSection

            pitchSection

            if isModified {
                Divider()
                nowPlayingRow

                Button {
                    bakeToTrack()
                } label: {
                    Label("Write to Track", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(player.currentURL == nil)
                .help("Re-encode the file with current tempo + pitch baked in. Updates BPM/key tags and renames.")
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear { syncFields() }
        .onChange(of: player.tempoRate) { _, _ in syncFields() }
        .onChange(of: player.pitchCents) { _, _ in syncFields() }
    }

    private var originalRow: some View {
        HStack(spacing: 8) {
            Text("Original")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(originalBPM.map { "\($0) BPM" } ?? "—")
                .font(.caption.monospaced())
            Text("·").foregroundStyle(.tertiary)
            Text(originalKey.map(KeyNormalizer.toMusical) ?? "—")
                .font(.caption.monospaced())
            Spacer()
        }
    }

    private var tempoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tempo").font(.caption.bold())
                Spacer()
                TextField(
                    originalBPM != nil ? "BPM" : "rate",
                    text: $bpmText
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .frame(width: 80)
                .onSubmit { commitBPM() }
            }
            Slider(value: $player.tempoRate, in: 0.5...2.0)
        }
    }

    private var pitchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pitch").font(.caption.bold())
                Spacer()
                TextField("Cm or +2", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onSubmit { commitKey() }
            }
            HStack(spacing: 8) {
                Button { player.setPitchSemitones(semitones - 1) } label: {
                    Image(systemName: "minus.circle.fill")
                }
                Slider(value: Binding(
                    get: { Double(semitones) },
                    set: { player.setPitchSemitones(Int($0.rounded())) }
                ), in: -12...12)
                Button { player.setPitchSemitones(semitones + 1) } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var nowPlayingRow: some View {
        HStack(spacing: 8) {
            Text("Now")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(tweakedBPM.map { "\($0) BPM" } ?? String(format: "%.2fx", player.tempoRate))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.accent)
            Text("·").foregroundStyle(.tertiary)
            Text(tweakedKey ?? formatSemitones(semitones))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.accent)
            Spacer()
        }
    }

    private func syncFields() {
        bpmText = tweakedBPM.map(String.init) ?? String(format: "%.2f", player.tempoRate)
        keyText = tweakedKey ?? (semitones == 0 ? "" : formatSemitones(semitones))
    }

    private func commitBPM() {
        let raw = bpmText.trimmingCharacters(in: .whitespaces)
        if let target = Int(raw), let orig = originalBPM, orig > 0 {
            player.tempoRate = max(0.5, min(2.0, Float(target) / Float(orig)))
        } else if let rate = Float(raw) {
            player.tempoRate = max(0.5, min(2.0, rate))
        }
        syncFields()
    }

    private func commitKey() {
        let raw = keyText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { syncFields(); return }
        let cleaned = raw.replacingOccurrences(of: "st", with: "").trimmingCharacters(in: .whitespaces)
        if let n = Int(cleaned) {
            player.setPitchSemitones(max(-12, min(12, n)))
        } else if let orig = originalKey, let diff = KeyNormalizer.semitones(from: orig, to: raw) {
            player.setPitchSemitones(max(-12, min(12, diff)))
        }
        syncFields()
    }

    private func bakeToTrack() {
        guard let url = player.currentURL else { return }
        let bpm = tweakedBPM
        let key = tweakedKey  // already musical
        let rate = player.tempoRate
        let cents = player.pitchCents
        showPopover = false
        showAnalyzeSheet = true
        analyzer.bakeTweak(url, rate: rate, cents: cents, bpm: bpm, key: key) {
            // After bake, reset live tweak (file now has the change baked in)
            player.resetTempoAndPitch()
            // Refresh library scan to pick up renamed file + new tags
            if let folder = library.currentFolder {
                library.openFolder(folder)
            }
        }
    }

    private func formatSemitones(_ n: Int) -> String {
        if n == 0 { return "0 st" }
        return n > 0 ? "+\(n) st" : "\(n) st"
    }
}
