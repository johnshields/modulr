import Foundation
import Accelerate
import AVFoundation

/**
 * SpectrumGenerator
 * Offline STFT of an audio file via vDSP (Accelerate). Two entry points:
 *
 * - `generate(url:)` returns a full time × frequency dB matrix for the Spek-style
 *   heatmap (SpectrumSheet).
 * - `generateBinRanges(url:ranges:sampleStride:)` streams the STFT and only
 *   keeps the bins we care about — for cheap per-track verdicts in QualityCache
 *   without holding ~50 MB of float data in memory per file.
 *
 * Both share `iterateSTFT` so FFT params stay consistent: 4096-sample Hann
 * window, 50% overlap, dB-clamped to [minDB, maxDB].
 */
enum SpectrumGenerator {
    static let fftSize = 4096
    static let hopSize = 2048
    static let minDB: Float = -120
    static let maxDB: Float = 0

    struct Spectrum {
        let timeColumns: Int
        let freqBins: Int
        let data: [Float]
        let sampleRate: Double
        let duration: TimeInterval
    }

    /// Spectrum-frequency bins corresponding to [hzLow, hzHigh] for a given sample rate.
    static func binRange(hzLow: Double, hzHigh: Double, sampleRate: Double) -> ClosedRange<Int> {
        let bins = fftSize / 2
        let nyquist = sampleRate / 2
        let lo = max(0, min(bins - 1, Int(Double(bins - 1) * hzLow / nyquist)))
        let hi = max(lo, min(bins - 1, Int(Double(bins - 1) * hzHigh / nyquist)))
        return lo...hi
    }

    enum GenerateError: Error { case openFailed, allocFailed, readFailed }

    /// Full spectrum for visualisation.
    static func generate(url: URL) async throws -> Spectrum {
        let pcm = try loadMonoPCM(url: url)
        let bins = fftSize / 2
        let numWindows = max(1, (pcm.frames - fftSize) / hopSize + 1)
        var output = [Float](repeating: minDB, count: numWindows * bins)

        try iterateSTFT(mono: pcm.mono, frames: pcm.frames, stride: 1) { index, magsDB in
            let offset = index * bins
            for b in 0..<bins {
                output[offset + b] = magsDB[b]
            }
        }

        return Spectrum(
            timeColumns: numWindows,
            freqBins: bins,
            data: output,
            sampleRate: pcm.sampleRate,
            duration: Double(pcm.frames) / pcm.sampleRate
        )
    }

    /// Streaming verdict pipeline. Collects dB values only in the provided bin
    /// ranges so memory stays tiny regardless of track length. `sampleStride`
    /// skips windows for speed when sub-sampling is acceptable (e.g. >1 keeps
    /// every Nth window).
    struct RangeSample {
        let range: ClosedRange<Int>
        var values: [Float] = []
    }

    static func collectBinRanges(
        url: URL,
        ranges: [ClosedRange<Int>],
        sampleStride: Int = 1
    ) async throws -> (sampleRate: Double, samples: [RangeSample]) {
        let pcm = try loadMonoPCM(url: url)
        var samples = ranges.map { RangeSample(range: $0) }
        try iterateSTFT(
            mono: pcm.mono,
            frames: pcm.frames,
            stride: max(1, sampleStride)
        ) { _, magsDB in
            for i in 0..<samples.count {
                let r = samples[i].range
                for b in r.lowerBound...r.upperBound {
                    samples[i].values.append(magsDB[b])
                }
            }
        }
        return (pcm.sampleRate, samples)
    }

    // Shared STFT plumbing

    private struct MonoPCM {
        let mono: [Float]
        let frames: Int
        let sampleRate: Double
    }

    private static func loadMonoPCM(url: URL) throws -> MonoPCM {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)
        else { throw GenerateError.allocFailed }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else { throw GenerateError.readFailed }
        let frames = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        let mono = downmix(channelData: channelData, frames: frames, channels: channels)
        return MonoPCM(mono: mono, frames: frames, sampleRate: format.sampleRate)
    }

    /// Runs the STFT and yields each window's dB magnitudes (length `bins`)
    /// to `onWindow`. `stride` skips windows (1 = every window).
    private static func iterateSTFT(
        mono: [Float],
        frames: Int,
        stride: Int,
        onWindow: (_ windowIndex: Int, _ magnitudesDB: [Float]) -> Void
    ) throws {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        else { throw GenerateError.allocFailed }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let bins = fftSize / 2
        let numWindows = max(1, (frames - fftSize) / hopSize + 1)

        var realp = [Float](repeating: 0, count: bins)
        var imagp = [Float](repeating: 0, count: bins)
        var windowed = [Float](repeating: 0, count: fftSize)
        var magsSq = [Float](repeating: 0, count: bins)

        var w = 0
        while w < numWindows {
            let start = w * hopSize
            guard start + fftSize <= frames else { break }
            vDSP_vmul(mono.withUnsafeBufferPointer { $0.baseAddress! + start }, 1,
                      window, 1, &windowed, 1, vDSP_Length(fftSize))

            realp.withUnsafeMutableBufferPointer { rPtr in
                imagp.withUnsafeMutableBufferPointer { iPtr in
                    var split = DSPSplitComplex(realp: rPtr.baseAddress!,
                                                imagp: iPtr.baseAddress!)
                    windowed.withUnsafeBufferPointer { wPtr in
                        wPtr.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self, capacity: bins
                        ) { cPtr in
                            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(bins))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magsSq, 1, vDSP_Length(bins))

                    var one: Float = 1
                    vDSP_vdbcon(magsSq, 1, &one, &magsSq, 1, vDSP_Length(bins), 0)
                    for b in 0..<bins {
                        magsSq[b] = max(minDB, min(maxDB, magsSq[b]))
                    }
                }
            }
            onWindow(w, magsSq)
            w += stride
        }
    }

    private static func downmix(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frames: Int, channels: Int
    ) -> [Float] {
        var mono = [Float](repeating: 0, count: frames)
        if channels == 1 {
            mono.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: channelData[0], count: frames)
            }
            return mono
        }
        let scale = 1.0 / Float(channels)
        for c in 0..<channels {
            let src = channelData[c]
            mono.withUnsafeMutableBufferPointer { dst in
                vDSP_vsma(src, 1, [scale], dst.baseAddress!, 1,
                          dst.baseAddress!, 1, vDSP_Length(frames))
            }
        }
        return mono
    }
}

/**
 * SpectrumImageRenderer
 * Turns a Spectrum into a CGImage. Each pixel (x, y) maps to one time column +
 * one linearly-spaced frequency bin (Spek convention). Magma-style palette.
 */
enum SpectrumImageRenderer {
    static func render(_ spectrum: SpectrumGenerator.Spectrum,
                       width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              spectrum.timeColumns > 0, spectrum.freqBins > 1 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let timeScale = Float(spectrum.timeColumns) / Float(width)
        let freqScale = Float(spectrum.freqBins - 1) / Float(height - 1)

        for x in 0..<width {
            let col = min(spectrum.timeColumns - 1, Int(Float(x) * timeScale))
            for y in 0..<height {
                let bin = min(spectrum.freqBins - 1,
                              Int(Float(height - 1 - y) * freqScale))
                let db = spectrum.data[col * spectrum.freqBins + bin]
                let v = (db - SpectrumGenerator.minDB) /
                    (SpectrumGenerator.maxDB - SpectrumGenerator.minDB)
                let (r, g, b) = palette(max(0, min(1, v)))
                let i = (y * width + x) * 4
                pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b; pixels[i + 3] = 255
            }
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// Magma-style palette stops: black → purple → magenta → red → orange → yellow → white.
    private static let paletteStops: [(Float, Float, Float, Float)] = [
        (0.00, 0,   0,   0),
        (0.15, 40,  10,  80),
        (0.30, 110, 30,  130),
        (0.45, 180, 40,  110),
        (0.60, 230, 70,  60),
        (0.75, 245, 140, 35),
        (0.88, 250, 220, 80),
        (1.00, 255, 255, 240),
    ]

    static func palette(_ v: Float) -> (UInt8, UInt8, UInt8) {
        let clamped = max(0, min(1, v))
        for i in 0..<(paletteStops.count - 1) {
            let a = paletteStops[i], b = paletteStops[i + 1]
            if clamped <= b.0 {
                let t = (clamped - a.0) / (b.0 - a.0)
                let r = a.1 + (b.1 - a.1) * t
                let g = a.2 + (b.2 - a.2) * t
                let bl = a.3 + (b.3 - a.3) * t
                return (UInt8(r), UInt8(g), UInt8(bl))
            }
        }
        let last = paletteStops.last!
        return (UInt8(last.1), UInt8(last.2), UInt8(last.3))
    }
}
