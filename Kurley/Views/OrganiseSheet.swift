import SwiftUI
import AppKit

struct OrganiseSheet: View {
    let initialOrder: [Track]
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var items: [Track] = []
    @State private var padding: Int = 3
    @State private var dragID: UUID?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Organise Tracks").font(.headline)
                    Text("Drag rows to reorder. Apply renames + writes ID3 title.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Digits", selection: $padding) {
                    Text("01").tag(2); Text("001").tag(3); Text("0001").tag(4)
                }
                .pickerStyle(.segmented).fixedSize()
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, t in
                        row(idx: idx, t: t)
                            .onDrag {
                                dragID = t.id
                                return NSItemProvider(object: t.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: RowDropDelegate(
                                target: t, items: $items, dragID: $dragID
                            ))
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 380)
            .background(Color.black.opacity(0.2))

            Divider()

            HStack {
                Menu("Sort") {
                    Button("BPM ascending") { withAnimation { items.sort { ($0.bpm ?? 0) < ($1.bpm ?? 0) } } }
                    Button("BPM descending") { withAnimation { items.sort { ($0.bpm ?? 0) > ($1.bpm ?? 0) } } }
                    Button("Key") { withAnimation { items.sort { ($0.key ?? "") < ($1.key ?? "") } } }
                    Button("Title") { withAnimation { items.sort { $0.title < $1.title } } }
                    Button("Reverse") { withAnimation { items.reverse() } }
                }
                .fixedSize()

                Spacer()

                if let err = error { Text(err).foregroundStyle(.secondary).font(.caption) }

                Button("Cancel") { dismiss() }
                Button("Apply") { apply() }.keyboardShortcut(.defaultAction).disabled(items.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 640, height: 560)
        .onAppear { items = initialOrder }
    }

    private static let accent = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)

    @ViewBuilder
    private func row(idx: Int, t: Track) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 16)
            Text(String(format: "%0\(padding)d", idx + 1))
                .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).lineLimit(1)
                if let a = t.artist {
                    Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let bpm = t.bpm { Text("\(bpm)").font(.caption).foregroundStyle(.secondary) }
            if let k = t.key { Text(KeyNormalizer.toMusical(k)).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(dragID == t.id ? Self.accent.opacity(0.25) : Color.white.opacity(idx % 2 == 0 ? 0.04 : 0))
        )
        .opacity(dragID == t.id ? 0.5 : 1)
    }

    private func apply() {
        do {
            try library.renumber(orderedIDs: items.map(\.id), padding: padding)
            dismiss()
        } catch {
            self.error = "Failed: \(error)"
        }
    }
}

struct RowDropDelegate: DropDelegate {
    let target: Track
    @Binding var items: [Track]
    @Binding var dragID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        dragID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragID, dragID != target.id,
              let from = items.firstIndex(where: { $0.id == dragID }),
              let to = items.firstIndex(where: { $0.id == target.id }) else { return }
        if items[to].id == self.dragID { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            let item = items.remove(at: from)
            items.insert(item, at: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
