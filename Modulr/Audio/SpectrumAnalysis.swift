import Foundation
import SwiftUI

/**
 * QualityVerdict
 * One-word judgment shown next to a track + colour + tooltip detail. Produced
 * by `SpectrumAnalysis.verdict(...)` or `SpectrumAnalysis.verdict(spectrum:)`.
 */
struct QualityVerdict: Hashable {
    let label: String
    let color: Color
    let detail: String

    static let unknown = QualityVerdict(
        label: "Unknown",
        color: .gray,
        detail: "Not enough headroom in the source to score."
    )

    /// Higher rank = better top-end. Used by enhancement modals to recommend
    /// whether to keep the result. Unknown = -1 so it never wins comparisons.
    var rank: Int {
        switch label {
        case "Cooked": return 0
        case "Muddy":  return 1
        case "Punchy": return 2
        case "Crisp":  return 3
        default:       return -1
        }
    }
}

/**
 * SpectrumAnalysis
 * Pure functions over Spectrum or raw dB samples. Two factories:
 *
 * - `verdict(spectrum:)` — uses an already-computed full Spectrum (sheet path).
 * - `verdict(loSamples:hiSamples:nyquist:)` — uses the streaming bin samples
 *   collected by `SpectrumGenerator.collectBinRanges` (cache path).
 *
 * Both converge through `gradeDrop(_:)` so the verdict scale stays consistent.
 */
enum SpectrumAnalysis {
    static let loBand: (Double, Double) = (1_000, 5_000)
    static let hiBand: (Double, Double) = (16_000, 20_000)
    static let minNyquist: Double = 16_000

    static func verdict(spectrum: SpectrumGenerator.Spectrum) -> QualityVerdict {
        guard spectrum.sampleRate / 2 > minNyquist else { return .unknown }
        let lo = SpectrumGenerator.binRange(hzLow: loBand.0, hzHigh: loBand.1,
                                            sampleRate: spectrum.sampleRate)
        let hi = SpectrumGenerator.binRange(hzLow: hiBand.0, hzHigh: hiBand.1,
                                            sampleRate: spectrum.sampleRate)
        let loEnergy = medianBand(spectrum: spectrum, bins: lo)
        let hiEnergy = medianBand(spectrum: spectrum, bins: hi)
        return gradeDrop(loEnergy: loEnergy, hiEnergy: hiEnergy)
    }

    static func verdict(loSamples: [Float], hiSamples: [Float],
                        sampleRate: Double) -> QualityVerdict {
        guard sampleRate / 2 > minNyquist else { return .unknown }
        let loEnergy = median(loSamples) ?? SpectrumGenerator.minDB
        let hiEnergy = median(hiSamples) ?? SpectrumGenerator.minDB
        return gradeDrop(loEnergy: loEnergy, hiEnergy: hiEnergy)
    }

    // Internals

    private static func gradeDrop(loEnergy: Float, hiEnergy: Float) -> QualityVerdict {
        guard loEnergy > -100 else { return .unknown }
        let drop = loEnergy - hiEnergy
        switch drop {
        case ..<10:
            return QualityVerdict(
                label: "Crisp",
                color: Color(red: 0.40, green: 0.95, blue: 0.55),
                detail: "Full bandwidth — clean top-end, high quality source."
            )
        case ..<20:
            return QualityVerdict(
                label: "Punchy",
                color: Color(red: 0.65, green: 0.85, blue: 0.40),
                detail: "Healthy top-end with minor roll-off."
            )
        case ..<30:
            return QualityVerdict(
                label: "Muddy",
                color: Color(red: 0.95, green: 0.80, blue: 0.25),
                detail: "Noticeable cutoff above 16 kHz — borderline source."
            )
        default:
            return QualityVerdict(
                label: "Cooked",
                color: Color(red: 0.95, green: 0.35, blue: 0.30),
                detail: "Sharp cliff above 16 kHz — likely upconverted from lossy source."
            )
        }
    }

    private static func medianBand(spectrum: SpectrumGenerator.Spectrum,
                                   bins: ClosedRange<Int>) -> Float {
        var collected: [Float] = []
        let step = max(1, spectrum.timeColumns / 200)
        for col in stride(from: 0, to: spectrum.timeColumns, by: step) {
            for b in bins {
                collected.append(spectrum.data[col * spectrum.freqBins + b])
            }
        }
        return median(collected) ?? SpectrumGenerator.minDB
    }

    private static func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        var sorted = values
        sorted.sort()
        return sorted[sorted.count / 2]
    }
}
