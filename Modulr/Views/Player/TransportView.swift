import SwiftUI

struct TransportView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyze: Bool

    private var currentTaggable: URL? {
        guard let u = player.currentURL, TagIO.supportsTags(u) else { return nil }
        return u
    }

    @State private var autoPlay = true
    @State private var isCompact = false

    private static let autoPlayColor = Color(red: 0xff/255, green: 0x3b/255, blue: 0x3b/255)
    private static let shuffleColor  = Color(red: 0x2b/255, green: 0xd4/255, blue: 0x6a/255)

    private func chip(_ label: String, system: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isCompact {
                    Image(systemName: system)
                } else {
                    Label(label, systemImage: system)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(on ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(on ? tint.opacity(0.85) : Color.white.opacity(0.08))
        .cornerRadius(6)
        .help(label)
    }

    var body: some View {
        GeometryReader { geo in
            content
                .onAppear { isCompact = geo.size.width < 760 }
                .onChange(of: geo.size.width) { _, w in isCompact = w < 760 }
        }
        .frame(height: 44)
    }

    private var content: some View {
        HStack(spacing: 12) {
            chip("AutoPlay", system: "play.circle", on: autoPlay, tint: Self.autoPlayColor) { autoPlay.toggle() }
            chip("Shuffle", system: "shuffle", on: player.isShuffled, tint: Self.shuffleColor) { player.isShuffled.toggle() }

            Menu {
                Section("Analyse") {
                    Button {
                        guard let u = currentTaggable else { return }
                        analyzer.analyzeFile(u, rename: analyzer.renameAfter) {}
                        showAnalyze = true
                    } label: {
                        Label("Current Track", systemImage: "music.note")
                    }
                    .disabled(currentTaggable == nil)

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
                }

                Section("Cleanup") {
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.syncFilenameToTags(cur) {}
                        showAnalyze = true
                    } label: {
                        Label("Rename to DJ Format", systemImage: "textformat.abc")
                    }
                    .disabled(library.currentFolder == nil)
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.resetFolder(cur) {}
                        showAnalyze = true
                    } label: {
                        Label("Reset Names (clean)", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(library.currentFolder == nil)
                }

                Section("Convert") {
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.convertFolderToMP3(cur, deleteSource: false) {}
                        showAnalyze = true
                    } label: {
                        Label("Folder to MP3 (keep originals)",
                              systemImage: "waveform.path.badge.plus")
                    }
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.convertFolderToMP3(cur, deleteSource: true) {}
                        showAnalyze = true
                    } label: {
                        Label("Folder to MP3 (delete originals)",
                              systemImage: "trash")
                    }
                    .disabled(library.currentFolder == nil)
                }
            } label: {
                Group {
                    if isCompact {
                        Image(systemName: "waveform.badge.magnifyingglass")
                    } else {
                        Label("Analyse", systemImage: "waveform.badge.magnifyingglass")
                            .lineLimit(1).fixedSize()
                    }
                }
                .foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.accent.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(6)
            .help("Analyse")

            Menu {
                Section("Current Track") {
                    Button {
                        guard let u = currentTaggable else { return }
                        analyzer.normalizeFilePreview(u) {}
                        showAnalyze = true
                    } label: {
                        Label("Preview Gain", systemImage: "eye")
                    }
                    .disabled(currentTaggable == nil)
                    Button {
                        guard let u = currentTaggable else { return }
                        analyzer.normalizeFileApply(u) {}
                        showAnalyze = true
                    } label: {
                        Label("Boost Safe", systemImage: "wand.and.stars")
                    }
                    .disabled(currentTaggable == nil)
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
                Group {
                    if isCompact {
                        Image(systemName: "speaker.wave.2.fill")
                    } else {
                        Label("Loudness", systemImage: "speaker.wave.2.fill")
                            .lineLimit(1).fixedSize()
                    }
                }
                .foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)
            .help("Loudness")

            PitchPanel(player: player, showAnalyzeSheet: $showAnalyze)

            Spacer()

            HStack(spacing: 8) {
                OutputDeviceMenu()
                    .frame(width: 22, height: 22)
                Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.caption)
                VolumeSlider(value: $player.volume)
                    .frame(width: 110, height: 16)
            }
        }
        .foregroundStyle(.white)
        .tint(Theme.accent)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
    }
}

private struct VolumeSlider: View {
    @Binding var value: Float

    private static let track = LinearGradient(
        colors: [
            Color(red: 0x3e/255, green: 0xc5/255, blue: 0x5f/255),
            Color(red: 0xff/255, green: 0x8a/255, blue: 0x1e/255),
            Color(red: 1, green: 0.4, blue: 0.4),
        ],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = CGFloat(min(1, max(0, value)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                Capsule().fill(Self.track).frame(width: w, height: 4)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: frac * w, height: 4)
                    }
                Circle().fill(.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                    .offset(x: frac * w - 6.5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    value = Float(min(1, max(0, g.location.x / w)))
                }
            )
        }
    }
}
