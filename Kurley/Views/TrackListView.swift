import SwiftUI
import AppKit

struct TrackListView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyze: Bool
    let onPlay: (URL) -> Void

    @State private var selection: Track.ID?
    @State private var sortOrder: [KeyPathComparator<Track>] = [.init(\.title)]
    @State private var renameTrack: Track?
    @State private var tagTrack: Track?
    @State private var deleteTrack: Track?
    @State private var showOrganise = false

    private static let accent = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)

    private var sorted: [Track] { library.tracks.sorted(using: sortOrder) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(library.tracks.count) tracks")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    showOrganise = true
                } label: {
                    Label("Edit Order", systemImage: "list.number")
                }
                .controlSize(.small)
                .disabled(library.tracks.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            Table(sorted, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.title) { t in
                    HStack {
                        Button {
                            library.toggleFavorite(t.id)
                        } label: {
                            Image(systemName: library.favorites.contains(t.id) ? "star.fill" : "star")
                        }.buttonStyle(.borderless)
                        Text(t.title).lineLimit(1)
                    }
                                    }
                .width(min: 220, ideal: 320)

                TableColumn("Artist", value: \.artistSort) { t in
                    Text(t.artistDisplay)
                        .lineLimit(1)
                        .foregroundStyle(t.artist == nil ? .secondary : .primary)
                                        }
                .width(min: 140, ideal: 200)

                TableColumn("BPM", value: \.bpmSort) { t in
                    Text(t.bpmDisplay)                }
                .width(min: 50, ideal: 60, max: 80)

                TableColumn("Key", value: \.keySort) { t in
                    Text(t.keyDisplay)                }
                .width(min: 50, ideal: 60, max: 80)

                TableColumn("Duration", value: \.duration) { t in
                    Text(format(t.duration))                }
                .width(min: 70, ideal: 80, max: 100)

                TableColumn("Type", value: \.fileType) { t in
                    Text(t.fileType)                }
                .width(min: 50, ideal: 60, max: 80)
            }
            .contextMenu(forSelectionType: Track.ID.self) { ids in
                if let id = ids.first, let t = sorted.first(where: { $0.id == id }) {
                    menu(for: t)
                }
            }
            .onChange(of: selection) { _, new in
                guard let id = new, let t = sorted.first(where: { $0.id == id }) else { return }
                play(t)
            }
        }
        .tint(Self.accent)
        .sheet(item: $renameTrack) { t in RenameSheet(track: t).environmentObject(library) }
        .sheet(item: $tagTrack) { t in TagEditSheet(track: t).environmentObject(library) }
        .sheet(isPresented: $showOrganise) {
            OrganiseSheet(initialOrder: sorted)
                .environmentObject(library)
                .tint(Self.accent)
        }
        .alert(item: $deleteTrack) { t in
            Alert(
                title: Text("Move to Trash?"),
                message: Text(t.url.lastPathComponent),
                primaryButton: .destructive(Text("Move to Trash")) {
                    try? library.deleteTrack(t.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    @ViewBuilder
    private func menu(for t: Track) -> some View {
        Button("Play") { play(t) }
        Button("Rename…") { renameTrack = t }
        Button("Edit Tags…") { tagTrack = t }.disabled(!TagIO.isMP3(t.url))
        Button("Analyze BPM/Key") {
            analyzer.analyzeFile(t.url) {}
            showAnalyze = true
        }.disabled(!TagIO.isMP3(t.url))
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([t.url]) }
        Button(role: .destructive) { deleteTrack = t } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private func play(_ t: Track) {
        onPlay(t.url)
    }

    private func format(_ s: TimeInterval) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}
