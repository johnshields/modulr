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
    private var audioFile: AVAudioFile?
    private var displayLink: Timer?
    private var seekOffset: TimeInterval = 0

    init() {
        engine.attach(playerNode)
        engine.attach(eq)
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        installLevelTap()
        try? engine.start()
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
