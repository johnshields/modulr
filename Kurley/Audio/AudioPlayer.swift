import Foundation
import AVFoundation
import Combine

/**
 * AudioPlayer
 * Wraps AVAudioEngine + AVAudioPlayerNode for playback, EQ, and metering
 */
final class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentURL: URL?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 { didSet { engine.mainMixerNode.outputVolume = volume } }
    @Published var isShuffled = false
    @Published var isMuted = false { didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : volume } }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 10)
    private var audioFile: AVAudioFile?
    private var displayLink: Timer?

    init() {
        engine.attach(playerNode)
        engine.attach(eq)
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        try? engine.start()
    }

    func load(_ url: URL) {
        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            currentURL = url
            duration = Double(file.length) / file.processingFormat.sampleRate
            playerNode.stop()
            playerNode.scheduleFile(file, at: nil)
        } catch {
            print("load fail: \(error)")
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
            self.currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
        }
    }
}
