import Foundation

/**
 * Shared display formatters. Each modal/view used to declare its own private
 * `format(TimeInterval)` helper — three copies of the same MM:SS code lived in
 * WaveformView, TrackListView and SpectrumSheet. Centralised here so callers
 * use the same humanisation everywhere.
 */
enum Formatters {
    /// Zero-padded `MM:SS` for table durations and waveform timers.
    static func mmss(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Compact `M:SS` for axis labels and other tight contexts.
    static func mss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "5 kHz" above 1k, "850 Hz" below. Drops decimals so axes stay tidy.
    static func hertz(_ hz: Double) -> String {
        hz >= 1_000 ? "\(Int(hz / 1_000)) kHz" : "\(Int(hz)) Hz"
    }
}
