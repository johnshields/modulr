import Foundation
import AVFoundation
import SwiftUI

/**
 * QualityCache
 * Lazily computes a Spek-style verdict per track URL via the lightweight
 * streaming STFT in `SpectrumGenerator.collectBinRanges`. Results cache in
 * memory for the session; cells call `requestVerdict` from `.onAppear`.
 * Concurrency is capped so scrolling a big folder doesn't peg the CPU.
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

    /// Sampling stride for the streaming STFT — every Nth window. Keeps the
    /// verdict fast (~200 ms per minute of audio) without changing the result
    /// since the verdict is a median over the band.
    private static let windowStride = 4

    func verdict(for url: URL) -> QualityVerdict? { verdicts[url] }

    /// Evict the cached verdict for a URL whose file content has changed
    /// (after Brighten / Loudness replace, etc.) so a fresh score is computed
    /// the next time the row appears.
    func invalidate(_ url: URL) {
        verdicts.removeValue(forKey: url)
        pending.remove(url)
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

    // MARK: - Compute

    /// Runs the async streaming collector inside a semaphore so the
    /// OperationQueue worker can wait synchronously for it.
    private static func computeBlocking(url: URL) -> QualityVerdict? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: QualityVerdict?
        Task {
            do {
                let probeSampleRate = try probeSampleRate(url: url)
                let loBins = SpectrumGenerator.binRange(
                    hzLow: SpectrumAnalysis.loBand.0,
                    hzHigh: SpectrumAnalysis.loBand.1,
                    sampleRate: probeSampleRate
                )
                let hiBins = SpectrumGenerator.binRange(
                    hzLow: SpectrumAnalysis.hiBand.0,
                    hzHigh: SpectrumAnalysis.hiBand.1,
                    sampleRate: probeSampleRate
                )
                let (sampleRate, samples) = try await SpectrumGenerator.collectBinRanges(
                    url: url,
                    ranges: [loBins, hiBins],
                    sampleStride: windowStride
                )
                result = SpectrumAnalysis.verdict(
                    loSamples: samples[0].values,
                    hiSamples: samples[1].values,
                    sampleRate: sampleRate
                )
            } catch {
                result = nil
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private static func probeSampleRate(url: URL) throws -> Double {
        // AVAudioFile reads the format header without decoding samples, so the
        // probe is effectively free and lets us pre-compute the bin ranges.
        let file = try AVAudioFile(forReading: url)
        return file.processingFormat.sampleRate
    }
}
