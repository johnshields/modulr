import Foundation
import AVFoundation

/**
 * WaveformLoader
 * Reads audio file and returns downsampled peak array for waveform render
 */
enum WaveformLoader {
    static func peaks(from url: URL, targetCount: Int = 6000) async -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return [] }
        do { try file.read(into: buffer) } catch { return [] }
        guard let channelData = buffer.floatChannelData?[0] else { return [] }

        let total = Int(buffer.frameLength)
        let bucket = max(1, total / targetCount)
        var out: [Float] = []
        out.reserveCapacity(targetCount)
        var i = 0
        while i < total {
            var peak: Float = 0
            let end = min(i + bucket, total)
            for j in i..<end {
                let v = abs(channelData[j])
                if v > peak { peak = v }
            }
            out.append(peak)
            i += bucket
        }
        return out
    }
}
