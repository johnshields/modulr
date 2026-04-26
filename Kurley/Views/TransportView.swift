import SwiftUI

struct TransportView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyze: Bool

    private static let accent = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)

    private var currentMP3: URL? {
        guard let u = player.currentURL, TagIO.isMP3(u) else { return nil }
        return u
    }

    @State private var autoPlay = true

    private func chip(_ label: String, system: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(on ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(on ? Self.accent.opacity(0.85) : Color.white.opacity(0.08))
        .cornerRadius(6)
    }

    var body: some View {
        HStack(spacing: 12) {
            chip("AutoPlay", system: "play.circle", on: autoPlay) { autoPlay.toggle() }
            chip("Shuffle", system: "shuffle", on: player.isShuffled) { player.isShuffled.toggle() }

            Menu {
                Section("Analyse") {
                    Button {
                        guard let u = currentMP3 else { return }
                        analyzer.analyzeFile(u, rename: analyzer.renameAfter) {}
                        showAnalyze = true
                    } label: {
                        Label("Current Track", systemImage: "music.note")
                    }
                    .disabled(currentMP3 == nil)

                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.analyzeFolder(cur, rename: analyzer.renameAfter) {}
                        showAnalyze = true
                    } label: {
                        Label("Whole Folder", systemImage: "folder")
                    }
                    .disabled(library.currentFolder == nil)
                }

                Section("Options") {
                    Toggle(isOn: $analyzer.renameAfter) {
                        Label("Rename file after analyse", systemImage: "pencil.line")
                    }
                    Toggle(isOn: $analyzer.keepOrder) {
                        Label("Keep order (NNN_ prefix)", systemImage: "list.number")
                    }
                    .disabled(!analyzer.renameAfter)
                }

                Section("Cleanup") {
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.resetFolder(cur, keepNumbers: false) {}
                        showAnalyze = true
                    } label: {
                        Label("Reset Names (clean)", systemImage: "arrow.counterclockwise")
                    }
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.resetFolder(cur, keepNumbers: true) {}
                        showAnalyze = true
                    } label: {
                        Label("Reset Names (keep order)", systemImage: "list.number")
                    }
                    .disabled(library.currentFolder == nil)
                }
            } label: {
                Label("Analyse", systemImage: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Self.accent.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Self.accent.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(6)

            Menu {
                Section("Current Track") {
                    Button {
                        guard let u = currentMP3 else { return }
                        analyzer.normalizeFilePreview(u) {}
                        showAnalyze = true
                    } label: {
                        Label("Preview Gain", systemImage: "eye")
                    }
                    .disabled(currentMP3 == nil)
                    Button {
                        guard let u = currentMP3 else { return }
                        analyzer.normalizeFileApply(u) {}
                        showAnalyze = true
                    } label: {
                        Label("Boost Safe", systemImage: "wand.and.stars")
                    }
                    .disabled(currentMP3 == nil)
                }
                Section("Whole Folder") {
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.normalizePreview(cur) {}
                        showAnalyze = true
                    } label: {
                        Label("Preview Gain Plan", systemImage: "eye")
                    }
                    .disabled(library.currentFolder == nil)
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.normalizeApply(cur) {}
                        showAnalyze = true
                    } label: {
                        Label("Match Loudest", systemImage: "wand.and.stars")
                    }
                    .disabled(library.currentFolder == nil)
                }
            } label: {
                Label("Loudness", systemImage: "speaker.wave.2.fill")
                    .foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.caption)
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 110)
            }
        }
        .foregroundStyle(.white)
        .tint(Self.accent)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
    }
}
