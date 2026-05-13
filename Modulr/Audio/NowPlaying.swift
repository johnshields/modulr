import Foundation
import MediaPlayer
import AVFoundation
import AppKit

/**
 * NowPlaying
 * Bridges AudioPlayer state to MPNowPlayingInfoCenter + MPRemoteCommandCenter
 * Shows in menu bar / Control Center / lock screen widgets
 */
final class NowPlaying {
    static let shared = NowPlaying()

    private let center = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()

    weak var player: AudioPlayer?
    var onNext: (() -> Void)?
    var onPrev: (() -> Void)?

    private init() {}

    func setup(player: AudioPlayer, onNext: @escaping () -> Void, onPrev: @escaping () -> Void) {
        self.player = player
        self.onNext = onNext
        self.onPrev = onPrev

        commands.playCommand.addTarget { [weak self] _ in
            self?.player?.play(); return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause(); return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.player?.toggle(); return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?(); return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrev?(); return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.player?.seek(to: e.positionTime)
            return .success
        }
    }

    func update(title: String, artist: String?, artwork: NSImage?) {
        guard let player else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        info[MPMediaItemPropertyPlaybackDuration] = player.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? 1.0 : 0.0
        if let artwork {
            let art = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            info[MPMediaItemPropertyArtwork] = art
        }
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }

    func updatePlaybackState() {
        guard let player else { return }
        var info = center.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? 1.0 : 0.0
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }

    func clear() {
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }
}
