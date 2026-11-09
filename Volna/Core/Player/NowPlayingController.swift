import MediaPlayer
import UIKit

@MainActor
protocol NowPlayingDelegate: AnyObject {
    func remotePlay()
    func remotePause()
    func remoteToggle()
    func remoteNext()
    func remotePrevious()
    func remoteSeek(to time: TimeInterval)
    func remoteSkipForward(_ interval: TimeInterval)
    func remoteSkipBackward(_ interval: TimeInterval)
    func remoteToggleLike()
}

@MainActor
final class NowPlayingController {
    weak var delegate: NowPlayingDelegate?

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var artwork: MPMediaItemArtwork?
    private var configured = false

    init() {
        configureCommands()
    }

    func update(
        track: Track?,
        elapsed: TimeInterval,
        duration: TimeInterval,
        rate: Double,
        isPlaying: Bool,
        queueIndex: Int,
        queueCount: Int
    ) {
        guard let track else {
            clear()
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: "SoundCloud",
            MPMediaItemPropertyPlaybackDuration: max(duration, track.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? max(1.0, rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queueIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: max(queueCount, 1)
        ]

        if let permalink = track.permalinkURL {
            info[MPNowPlayingInfoPropertyExternalContentIdentifier] = permalink.absoluteString
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    func updateArtwork(_ image: UIImage?) {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            artwork = nil
            return
        }
        artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPMediaItemPropertyArtwork] = artwork
        infoCenter.nowPlayingInfo = info
    }

    func clear() {
        artwork = nil
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
    }

    private func configureCommands() {
        guard !configured else { return }
        configured = true

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.delegate?.remotePlay() }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.delegate?.remotePause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.delegate?.remoteToggle() }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.delegate?.remoteNext() }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.delegate?.remotePrevious() }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.delegate?.remoteSeek(to: positionEvent.positionTime) }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.delegate?.remoteSkipForward(interval) }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.delegate?.remoteSkipBackward(interval) }
            return .success
        }

        commandCenter.likeCommand.isEnabled = true
        commandCenter.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.delegate?.remoteToggleLike() }
            return .success
        }
    }
}
