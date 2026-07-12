import SwiftUI

/**
 * EnhancementPhase
 * Shared finite-state-machine ConvertSheet / BrightenSheet / LoudnessSheet all
 * walk: preview the action -> ffmpeg working -> done with verdict -> error.
 */
enum EnhancementPhase { case preview, working, done, error }

/**
 * SheetLifecycle
 * Shared open/cancel/finish flow for the enhancement modals, which all reload
 * the folder on success and discard the in-progress sibling on cancel.
 */
struct SheetLifecycle {
    let library: Library
    let analyzer: Analyzer
    let targetURL: URL
    let dismiss: DismissAction

    func finish() {
        if let folder = library.currentFolder { library.openFolder(folder) }
        dismiss()
    }

    func cancel() {
        analyzer.cancel()
        try? FileManager.default.removeItem(at: targetURL)
        dismiss()
    }

    func discard() {
        try? FileManager.default.removeItem(at: targetURL)
        finish()
    }

    func closeFromX(phase: EnhancementPhase) {
        switch phase {
        case .preview, .error: dismiss()
        case .working: cancel()
        case .done: discard()
        }
    }
}
