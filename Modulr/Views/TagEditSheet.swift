import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TagEditSheet: View {
    let track: Track
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var meta = TrackMeta()
    @State private var bpmText = ""
    @State private var yearText = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var artwork: NSImage?
    @State private var showFinder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Track Info").font(.headline)
            Text(track.url.lastPathComponent).font(.caption).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.4))
                        if let art = artwork {
                            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 120, height: 120)
                    HStack(spacing: 6) {
                        Button("Replace…") { pickArtwork() }
                        Button("Find") { showFinder = true }
                        Button("Remove") { removeArt() }.disabled(artwork == nil)
                    }
                    .controlSize(.small)
                }

                Form {
                    TextField("Title", text: $meta.title)
                    TextField("Artist", text: $meta.artist)
                    TextField("Album", text: $meta.album)
                    TextField("Genre", text: $meta.genre)
                    TextField("BPM", text: $bpmText)
                    TextField("Year", text: $yearText)
                }
            }

            if let err = error {
                Text(err).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
        .tint(Theme.accent)
        .overlay(alignment: .topTrailing) {
            MacCloseButton { dismiss() }
        }
        .sheet(isPresented: $showFinder) {
            ArtworkFinderSheet(track: track) { data, mime in
                library.setArtwork(track.url, imageData: data, mime: mime)
                if let img = NSImage(data: data) { artwork = img }
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            do {
                meta = try TagIO.read(track.url)
                bpmText = meta.bpm.map(String.init) ?? ""
                yearText = meta.year.map(String.init) ?? ""
            } catch {
                self.error = "Read failed: \(error)"
            }
            artwork = await ArtworkLoader.load(track.url)
        }
    }

    private func pickArtwork() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        library.setArtwork(track.url, imageData: data, mime: mime)
        if let img = NSImage(data: data) { artwork = img }
    }

    private func removeArt() {
        library.removeArtwork(track.url)
        artwork = nil
    }

    private func save() {
        meta.bpm = Int(bpmText.trimmingCharacters(in: .whitespaces))
        meta.year = Int(yearText.trimmingCharacters(in: .whitespaces))
        do {
            try library.updateTags(track.id, meta: meta)
            dismiss()
        } catch {
            self.error = "Write failed: \(error)"
        }
    }
}

struct RenameSheet: View {
    let track: Track
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename File").font(.headline)
            TextField("New name (no extension)", text: $name)
            if let err = error {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button("Rename") { commit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .tint(Theme.accent)
        .overlay(alignment: .topTrailing) {
            MacCloseButton { dismiss() }
        }
        .onAppear { name = track.url.deletingPathExtension().lastPathComponent }
    }

    private func commit() {
        do {
            try library.rename(track.id, to: name)
            dismiss()
        } catch {
            self.error = "Rename failed: \(error)"
        }
    }
}
