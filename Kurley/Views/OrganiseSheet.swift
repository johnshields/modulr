import SwiftUI

/**
 * Drop delegate used by edit-mode track list to reorder rows during drag.
 */
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
