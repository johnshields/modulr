import Foundation
import AVFoundation
import SwiftUI

/**
 * QualityCache
 * Lazy per-URL verdicts via `SpectrumGenerator.findCutoff`. Cells request
 * scores from `.onAppear`; results live in memory for the session. Two
 * concurrent operations cap CPU while scrolling large folders.
 */
@MainActor
final class QualityCache: ObservableObject {
    @Published private(set) var verdicts: [URL: QualityVerdict] = [:]

    private var pending: Set<URL> = []
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .utility
        return q
    }()

    init() {
        NotificationCenter.default.addObserver(
            forName: .libraryFolderReloaded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.invalidateAll() }
        }
    }

    func verdict(for url: URL) -> QualityVerdict? { verdicts[url] }

    func invalidate(_ url: URL) {
        verdicts.removeValue(forKey: url)
        pending.remove(url)
    }

    func invalidateAll() {
        verdicts.removeAll()
        pending.removeAll()
    }

    func requestVerdict(_ url: URL) {
        guard verdicts[url] == nil, !pending.contains(url) else { return }
        pending.insert(url)
        queue.addOperation { [weak self] in
            let verdict = Self.computeBlocking(url: url)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let v = verdict { self.verdicts[url] = v }
                self.pending.remove(url)
            }
        }
    }

    private static func computeBlocking(url: URL) -> QualityVerdict? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: QualityVerdict?
        Task {
            do {
                let cut = try await SpectrumGenerator.findCutoff(url: url)
                result = SpectrumAnalysis.verdict(
                    cutoffHz: cut.cutoffHz,
                    sampleRate: cut.sampleRate,
                    sourceURL: url
                )
            } catch {
                result = nil
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
}
