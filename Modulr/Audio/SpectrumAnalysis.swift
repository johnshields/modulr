import Foundation
import SwiftUI

/**
 * QualityVerdict
 * Label + colour + tooltip detail. Carries the detected cutoff so callers
 * (BrightenSheet) can branch on bandwidth without re-running the analysis.
 */
struct QualityVerdict: Hashable {
    let label: String
    let color: Color
    let detail: String
    /// Spectral cutoff in Hz. Nil for `.unknown`.
    var cutoffHz: Double? = nil
    /// Source sample rate in Hz.
    var sampleRateHz: Double? = nil

    static let unknown = QualityVerdict(
        label: "Unknown",
        color: .gray,
        detail: "Not enough headroom in the source to score."
    )

    var rank: Int {
        switch label {
        case "Cooked": return 0
        case "Muddy":  return 1
        case "Punchy": return 2
        case "Crisp":  return 3
        default:       return -1
        }
    }

    /// True when the cutoff sits at or above the healthy floor (default 19 kHz,
    /// proportional for low-Nyquist files). Used by BrightenSheet to nudge
    /// against exciting sources that already carry real top-end.
    var hasHealthyTop: Bool {
        guard let cutoff = cutoffHz, let sampleRate = sampleRateHz else { return false }
        let nyquist = sampleRate / 2
        let adjusted = min(SpectrumAnalysis.healthyCutoffHz, nyquist - 1000)
        return cutoff >= adjusted
    }
}

/**
 * SpectrumAnalysis
 * Cutoff-driven verdict modelled after fakeflac, Lossless Audio Checker and
 * Spectro. Thresholds in kHz:
 *
 *   >= 20.5  -> Crisp   (genuine lossless or 320 CBR LAME with no lowpass)
 *   >= 19.5  -> Punchy  (320 MP3 or transparent AAC >= 256 kbps)
 *   >= 17.5  -> Muddy   (192-256 MP3, FDK-AAC at default 17 kHz)
 *   >= 15.5  -> Cooked  (128-192 MP3 or low-rate AAC)
 *   <  15.5  -> Cooked  (<= 128 kbps source)
 *
 * AAC / m4a containers get a 1.5 kHz leniency offset because FDK-AAC plateaus
 * at 17 kHz at iTunes-radio rates.
 *
 * Refs:
 *   - mevdschee/fakeflac (cliff slope methodology)
 *   - getspectro.app blog "how-to-detect-fake-lossless"
 *   - Hennequin et al., ICASSP 2017 (Deezer Research)
 *   - Hydrogenaudio FDK-AAC and LAME wikis
 */
enum SpectrumAnalysis {
    /// Cutoff floor for the healthy-top check used by BrightenSheet.
    static let healthyCutoffHz: Double = 19_000

    /// File extensions treated as AAC for the container offset.
    private static let aacExtensions: Set<String> = ["m4a", "aac", "mp4"]
    private static let aacOffsetHz: Double = 1_500

    /// Tier minimums (Hz) for lossless/generic containers.
    private static let crispMinHz: Double = 20_500
    private static let punchyMinHz: Double = 19_500
    private static let muddyMinHz: Double = 17_500
    private static let cookedMinHz: Double = 15_500

    static func verdict(cutoffHz: Double, sampleRate: Double,
                        sourceURL: URL? = nil) -> QualityVerdict {
        let isAAC = sourceURL.map { aacExtensions.contains($0.pathExtension.lowercased()) } ?? false
        let offset: Double = isAAC ? aacOffsetHz : 0

        let crisp  = crispMinHz  - offset
        let punchy = punchyMinHz - offset
        let muddy  = muddyMinHz  - offset
        let cooked = cookedMinHz - offset

        func build(_ label: String, _ color: Color, _ detail: String) -> QualityVerdict {
            QualityVerdict(label: label, color: color, detail: detail,
                           cutoffHz: cutoffHz, sampleRateHz: sampleRate)
        }

        if cutoffHz >= crisp {
            return build("Crisp",
                         Color(red: 0.40, green: 0.95, blue: 0.55),
                         "Cutoff near Nyquist — full-bandwidth source.")
        }
        if cutoffHz >= punchy {
            return build("Punchy",
                         Color(red: 0.65, green: 0.85, blue: 0.40),
                         "Cutoff ≈ \(Self.kHz(cutoffHz)) — 320 MP3 or transparent AAC.")
        }
        if cutoffHz >= muddy {
            return build("Muddy",
                         Color(red: 0.95, green: 0.80, blue: 0.25),
                         "Cutoff ≈ \(Self.kHz(cutoffHz)) — likely 192–256 kbps MP3 / AAC.")
        }
        if cutoffHz >= cooked {
            return build("Cooked",
                         Color(red: 0.95, green: 0.35, blue: 0.30),
                         "Cutoff ≈ \(Self.kHz(cutoffHz)) — likely 128–192 kbps source.")
        }
        return build("Cooked",
                     Color(red: 0.95, green: 0.35, blue: 0.30),
                     "Cutoff ≈ \(Self.kHz(cutoffHz)) — likely ≤ 128 kbps source.")
    }

    /// Verdict from an already-rendered Spectrum (SpectrumSheet path). Uses
    /// the same smoothing + sweep helpers as `SpectrumGenerator.findCutoff`
    /// so the cache and the sheet agree on the cliff.
    static func verdict(spectrum: SpectrumGenerator.Spectrum,
                        sourceURL: URL? = nil) -> QualityVerdict {
        guard spectrum.timeColumns > 0, spectrum.freqBins > 1 else { return .unknown }
        var avg = [Float](repeating: 0, count: spectrum.freqBins)
        for col in 0..<spectrum.timeColumns {
            let base = col * spectrum.freqBins
            for b in 0..<spectrum.freqBins {
                avg[b] += spectrum.data[base + b]
            }
        }
        let denom = Float(spectrum.timeColumns)
        for b in 0..<spectrum.freqBins { avg[b] /= denom }

        let smoothed = SpectrumGenerator.smoothSpectrum(avg)
        let cutoff = SpectrumGenerator.sweepForCliff(
            spectrum: smoothed, sampleRate: spectrum.sampleRate
        )
        return verdict(cutoffHz: cutoff, sampleRate: spectrum.sampleRate, sourceURL: sourceURL)
    }

    private static func kHz(_ hz: Double) -> String {
        String(format: "%.1f kHz", hz / 1000)
    }
}
