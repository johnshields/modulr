import Foundation
import AVFoundation
import Combine

/**
 * AudioPlayer
 * Wraps AVAudioEngine + AVAudioPlayerNode for playback, EQ, and metering
 */
/**
 * High-frequency observable for currentTime + level meters
 * Kept separate so 50ms updates don't re-render the whole app
 */
final class PlaybackMonitor: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var levelL: Float = -60
    @Published var levelR: Float = -60
}

final class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentURL: URL?
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 { didSet { engine.mainMixerNode.outputVolume = volume } }
    @Published var isShuffled = false
    @Published var isMuted = false { didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : volume } }
    @Published var tempoRate: Float = 1.0 { didSet { applyRateAndPitch() } }
    @Published var pitchCents: Float = 0.0 { didSet { applyRateAndPitch() } }
    let pitchMode: PitchMode = .independent

    enum PitchMode: String, CaseIterable {
        case independent  // TimePitch — tempo + pitch independent
        case vinyl        // Varispeed — coupled, more natural for small tempo nudges
    }

    // Hot updates — own ObservableObject so they don't re-render the rest of the UI
    let monitor = PlaybackMonitor()
    var currentTime: TimeInterval {
        get { monitor.currentTime }
        set { monitor.currentTime = newValue }
    }
    var levelL: Float {
        get { monitor.levelL }
        set { monitor.levelL = newValue }
    }
    var levelR: Float {
        get { monitor.levelR }
        set { monitor.levelR = newValue }
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 10)
    private let timePitch = AVAudioUnitTimePitch()
    private let varispeed = AVAudioUnitVarispeed()
    private var audioFile: AVAudioFile?
    private var displayLink: Timer?
    private var seekOffset: TimeInterval = 0

    init() {
        engine.attach(playerNode)
        engine.attach(eq)
        engine.attach(timePitch)
        engine.attach(varispeed)
        // Max overlap = best phase-vocoder quality, more CPU/latency
        // Max overlap = best phase-vocoder quality (more CPU/latency)
        timePitch.overlap = 32
        // Force peak-locking on AUNewTimePitch for phase coherence.
        // Param ID 3 = kNewTimePitchParam_EnablePeakLocking on AUNewTimePitch.
        AudioUnitSetParameter(timePitch.audioUnit, 3, kAudioUnitScope_Global, 0, 1, 0)
        engine.connect(playerNode, to: varispeed, format: nil)
        engine.connect(varispeed, to: timePitch, format: nil)
        engine.connect(timePitch, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        installLevelTap()
        try? engine.start()
    }

    /**
     * Route tempo/pitch through TimePitch (independent) or Varispeed (coupled).
     * Vinyl mode gives more natural small adjustments; Independent for key changes
     * decoupled from tempo.
     */
    /**
     * Hybrid pipeline:
     *   - varispeed handles the tempo change (vinyl quality, no vocoder)
     *   - timePitch corrects the pitch back to the user's target
     * Result: speeding up does not raise the key (and vice versa) but the
     * tempo axis benefits from varispeed's smoother resampling.
     */
    private func applyRateAndPitch() {
        let r = max(0.5, min(2.0, tempoRate))
        let p = max(-2400, min(2400, pitchCents))
        let varispeedPitchCents = Float(log2(Double(r)) * 1200)
        varispeed.rate = r
        timePitch.rate = 1.0
        // Cancel the pitch lift from varispeed and apply the user's target pitch
        timePitch.pitch = p - varispeedPitchCents
    }

    /**
     * Shift pitch by integer semitones. 100 cents = 1 semitone.
     */
    func setPitchSemitones(_ semis: Int) {
        pitchCents = Float(semis) * 100
    }

    func resetTempoAndPitch() {
        tempoRate = 1.0
        pitchCents = 0
    }

    /**
     * Tap mixer output to compute per-buffer RMS dBFS for stereo meters
     */
    private func installLevelTap() {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let chs = Int(buffer.format.channelCount)
            var l: Float = 0
            var r: Float = 0
            for i in 0..<frameCount {
                let s0 = channels[0][i]
                l += s0 * s0
                if chs > 1 {
                    let s1 = channels[1][i]
                    r += s1 * s1
                }
            }
            let rmsL = sqrt(l / Float(max(1, frameCount)))
            let rmsR = chs > 1 ? sqrt(r / Float(max(1, frameCount))) : rmsL
            let dbL = 20 * log10(max(rmsL, 1e-6))
            let dbR = 20 * log10(max(rmsR, 1e-6))
            DispatchQueue.main.async {
                self.monitor.levelL = max(-60, min(0, dbL))
                self.monitor.levelR = max(-60, min(0, dbR))
            }
        }
    }

    func load(_ url: URL) {
        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            currentURL = url
            duration = Double(file.length) / file.processingFormat.sampleRate
            seekOffset = 0
            currentTime = 0
            resetTempoAndPitch()
            playerNode.stop()
            playerNode.scheduleFile(file, at: nil)
        } catch {
            print("load fail: \(error)")
        }
    }

    /**
     * Seek to absolute time. Reschedules segment from offset frame
     */
    func seek(to time: TimeInterval) {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        let sr = file.processingFormat.sampleRate
        let target = max(0, min(time, duration))
        let startFrame = AVAudioFramePosition(target * sr)
        let frameCount = AVAudioFrameCount(file.length - startFrame)
        guard frameCount > 0 else { return }

        playerNode.stop()
        seekOffset = target
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil)
        currentTime = target
        if wasPlaying {
            playerNode.play()
            startTick()
        }
    }

    func play() {
        guard audioFile != nil else { return }
        playerNode.play()
        isPlaying = true
        startTick()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        displayLink?.invalidate()
    }

    func toggle() { isPlaying ? pause() : play() }

    func stop() {
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        displayLink?.invalidate()
    }

    private func startTick() {
        displayLink?.invalidate()
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let nodeTime = self.playerNode.lastRenderTime,
                  let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
            self.currentTime = self.seekOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
        }
    }
}
