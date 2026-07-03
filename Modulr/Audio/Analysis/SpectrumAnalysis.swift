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
 * Quality verdict from the detected cutoff. Content reaching Nyquist is Crisp
 * (full bandwidth); a hard lossy shelf maps to a tier by its frequency in kHz:
 *
 *   Nyquist  -> Crisp   (no lossy shelf)
 *   >= 19.5  -> Punchy  (320 MP3 or transparent AAC >= 256 kbps)
 *   >= 17.5  -> Muddy   (192-256 kbps)
 *   >= 15.5  -> Cooked  (128-192 kbps)
 *   <  15.5  -> Cooked  (<= 128 kbps)
 *
 * AAC / m4a containers get a 1.5 kHz leniency offset.
 */
enum SpectrumAnalysis {
    /// Cutoff floor for the healthy-top check used by BrightenSheet.
    static let healthyCutoffHz: Double = 19_000

    /// File extensions treated as AAC for the container offset.
    private static let aacExtensions: Set<String> = ["m4a", "aac", "mp4"]
    private static let aacOffsetHz: Double = 1_500

    /// Shelf-frequency minimums (Hz) mapping a lossy ceiling to a codec tier.
    private static let punchyMinHz: Double = 19_500
    private static let muddyMinHz: Double = 17_500
    private static let cookedMinHz: Double = 15_500

    static func verdict(cutoffHz: Double, sampleRate: Double,
                        sourceURL: URL? = nil) -> QualityVerdict {
        let isAAC = sourceURL.map { aacExtensions.contains($0.pathExtension.lowercased()) } ?? false
        let offset: Double = isAAC ? aacOffsetHz : 0

        let punchy = punchyMinHz - offset
        let muddy  = muddyMinHz - offset
        let cooked = cookedMinHz - offset

        func build(_ label: String, _ color: Color, _ detail: String) -> QualityVerdict {
            QualityVerdict(label: label, color: color, detail: detail,
                           cutoffHz: cutoffHz, sampleRateHz: sampleRate)
        }

        // Content reaching Nyquist has no lossy shelf: genuine full bandwidth.
        if cutoffHz >= sampleRate / 2 - 500 {
            return build("Crisp",
                         Color(red: 0.40, green: 0.95, blue: 0.55),
                         "Full bandwidth to Nyquist.")
        }
        let shelf = "Hard shelf at \(Self.kHz(cutoffHz))"
        if cutoffHz >= punchy {
            return build("Punchy",
                         Color(red: 0.65, green: 0.85, blue: 0.40),
                         "\(shelf). 320 MP3 or transparent AAC.")
        }
        if cutoffHz >= muddy {
            return build("Muddy",
                         Color(red: 0.95, green: 0.80, blue: 0.25),
                         "\(shelf). Likely 192 to 256 kbps.")
        }
        if cutoffHz >= cooked {
            return build("Cooked",
                         Color(red: 0.95, green: 0.35, blue: 0.30),
                         "\(shelf). Likely 128 to 192 kbps.")
        }
        return build("Cooked",
                     Color(red: 0.95, green: 0.35, blue: 0.30),
                     "\(shelf). Likely 128 kbps or below.")
    }

    /// Verdict from an already-rendered Spectrum, using the same cutoff detection as findCutoff.
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
        let cutoff = SpectrumGenerator.detectCutoff(
            spectrum: smoothed, sampleRate: spectrum.sampleRate
        )
        return verdict(cutoffHz: cutoff, sampleRate: spectrum.sampleRate, sourceURL: sourceURL)
    }

    private static func kHz(_ hz: Double) -> String {
        String(format: "%.1f kHz", hz / 1000)
    }
}
