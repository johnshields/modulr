import Foundation
import AVFoundation

/**
 * WaveSlice
 * One downsampled column of the waveform: overall peak for bar height plus
 * per-band energy (low/mid/high) normalised 0...1 for rekordbox-style RGB.
 */
struct WaveSlice {
    let peak: Float
    let low: Float
    let mid: Float
    let high: Float
}

/**
 * WaveformLoader
 * Reads an audio file, splits it into three frequency bands with one-pole
 * crossovers, and returns downsampled slices carrying both amplitude and
 * per-band energy for an RGB waveform render.
 */
enum WaveformLoader {
    static func slices(from url: URL, targetCount: Int = 6000) async -> [WaveSlice] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return [] }
        do { try file.read(into: buffer) } catch { return [] }
        guard let channelData = buffer.floatChannelData?[0] else { return [] }

        let total = Int(buffer.frameLength)
        guard total > 0 else { return [] }
        let bucket = max(1, total / targetCount)

        let fs = Float(format.sampleRate)
        let aLow = onePole(cutoff: 300, sampleRate: fs)
        let aMid = onePole(cutoff: 2800, sampleRate: fs)

        var lpLow: Float = 0
        var lpMid: Float = 0
        var slices: [WaveSlice] = []
        slices.reserveCapacity(targetCount)

        var peakAcc: Float = 0
        var lowAcc: Float = 0, midAcc: Float = 0, highAcc: Float = 0
        var n = 0
        var lowMax: Float = 0.0001, midMax: Float = 0.0001, highMax: Float = 0.0001

        func flush() {
            let l = (lowAcc / Float(n)).squareRoot()
            let m = (midAcc / Float(n)).squareRoot()
            let h = (highAcc / Float(n)).squareRoot()
            lowMax = max(lowMax, l); midMax = max(midMax, m); highMax = max(highMax, h)
            slices.append(WaveSlice(peak: peakAcc, low: l, mid: m, high: h))
            peakAcc = 0; lowAcc = 0; midAcc = 0; highAcc = 0; n = 0
        }

        var i = 0
        while i < total {
            let x = channelData[i]
            lpLow += aLow * (x - lpLow)
            lpMid += aMid * (x - lpMid)
            let low = lpLow
            let mid = lpMid - lpLow
            let high = x - lpMid

            peakAcc = max(peakAcc, abs(x))
            lowAcc += low * low
            midAcc += mid * mid
            highAcc += high * high
            n += 1

            if n >= bucket { flush() }
            i += 1
        }
        if n > 0 { flush() }

        let invL = 1 / lowMax, invM = 1 / midMax, invH = 1 / highMax
        return slices.map {
            WaveSlice(peak: $0.peak,
                      low: min(1, $0.low * invL),
                      mid: min(1, $0.mid * invM),
                      high: min(1, $0.high * invH))
        }
    }

    private static func onePole(cutoff fc: Float, sampleRate fs: Float) -> Float {
        guard fs > 0 else { return 1 }
        return 1 / (1 + fs / (2 * .pi * fc))
    }
}
