import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PlaybackController: ObservableObject, NowPlayingDelegate {
    enum RepeatMode: String, CaseIterable {
        case off
        case all
        case one

        var symbol: String {
            switch self {
            case .off, .all: return "repeat"
            case .one: return "repeat.1"
            }
        }

        var isActive: Bool { self != .off }
    }

    @Published private(set) var currentTrack: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var notice: String?
    @Published private(set) var errorMessage: String?

    var fallbackProvider: ((Set<String>) async -> Track?)?

    private let api: SoundCloudAPIClient
    private let library: LibraryStore
    private let player = AVPlayer()
    private let nowPlaying = NowPlayingController()

    private var timeObserver: Any?
    private var itemCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var loadTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var playbackIntent = false
    private var fallbackAttempts = 0
    private var originalQueue: [Track]?
    private var originalIndex = 0
    private var wasPlayingBeforeInterruption = false

    /// Internal AVFoundation key used to attach the OAuth header to HLS requests.
    /// Keep playback behind this single seam so it can be replaced if Apple changes it.
    private let assetHeaderKey = "AVURLAssetHTTPHeaderFieldsKey"

    init(api: SoundCloudAPIClient, library: LibraryStore) {
        self.api = api
        self.library = library
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        nowPlaying.delegate = self
        configurePlayerObservers()
        configureAudioSessionObservers()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var hasTrack: Bool { currentTrack != nil }
    var canGoNext: Bool { !queue.isEmpty && (currentIndex + 1 < queue.count || repeatMode == .all) }

    func play(tracks: [Track], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let safeIndex = min(max(0, index), tracks.count - 1)
        queue = tracks
        currentIndex = safeIndex
        originalQueue = nil
        isShuffled = false
        fallbackAttempts = 0
        loadAndPlay(tracks[safeIndex], autoplay: true)
    }

    func play(_ track: Track) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            currentIndex = index
            loadAndPlay(track, autoplay: true)
        } else {
            queue = [track]
            currentIndex = 0
            loadAndPlay(track, autoplay: true)
        }
    }

    func enqueueNext(_ track: Track) {
        if queue.isEmpty {
            play(track)
            return
        }
        let insertIndex = min(currentIndex + 1, queue.count)
        queue.insert(track, at: insertIndex)
        showNotice("Добавлено в очередь")
    }

    func addToQueue(_ track: Track) {
        if queue.isEmpty {
            play(track)
        } else {
            queue.append(track)
            showNotice("Добавлено в конец очереди")
        }
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        fallbackAttempts = 0
        loadAndPlay(queue[index], autoplay: true)
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queue.remove(at: index)
        if queue.isEmpty {
            stop()
            return
        }
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, queue.count - 1)
            loadAndPlay(queue[currentIndex], autoplay: isPlaying)
        }
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying || playbackIntent {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let currentTrack else {
            if !queue.isEmpty {
                loadAndPlay(queue[min(currentIndex, queue.count - 1)], autoplay: true)
            }
            return
        }
        if player.currentItem == nil {
            loadAndPlay(currentTrack, autoplay: true)
            return
        }
        activateAudioSession()
        playbackIntent = true
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        playbackIntent = false
        player.pause()
        isPlaying = false
        isBuffering = false
        updateNowPlaying()
    }

    func stop() {
        loadGeneration += 1
        loadTask?.cancel()
        playbackIntent = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
        queue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        isPlaying = false
        isBuffering = false
        nowPlaying.clear()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            fallbackAttempts = 0
            loadAndPlay(queue[currentIndex], autoplay: true)
        } else if repeatMode == .all {
            currentIndex = 0
            fallbackAttempts = 0
            loadAndPlay(queue[0], autoplay: true)
        } else {
            pause()
            seek(to: duration)
        }
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
        } else {
            seek(to: 0)
            return
        }
        fallbackAttempts = 0
        loadAndPlay(queue[currentIndex], autoplay: true)
    }

    func seek(to time: TimeInterval) {
        guard duration > 0 || player.currentItem != nil else { return }
        let target = min(max(0, time), max(duration, 0))
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        updateNowPlaying()
    }

    func seek(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleShuffle() {
        guard let currentTrack else {
            isShuffled.toggle()
            return
        }

        if isShuffled {
            if let originalQueue, let index = originalQueue.firstIndex(where: { $0.id == currentTrack.id }) {
                queue = originalQueue
                currentIndex = index
            } else if let index = queue.firstIndex(where: { $0.id == currentTrack.id }) {
                currentIndex = index
            }
            isShuffled = false
        } else {
            originalQueue = queue
            originalIndex = currentIndex
            let remaining = queue.filter { $0.id != currentTrack.id }.shuffled()
            queue = [currentTrack] + remaining
            currentIndex = 0
            isShuffled = true
        }
        updateNowPlaying()
    }

    func toggleLikeCurrent() {
        guard let currentTrack else { return }
        let isLiked = library.toggleLike(currentTrack)
        showNotice(isLiked ? "Добавлено в избранное" : "Удалено из избранного")
    }

    // MARK: - Loading

    private func loadAndPlay(_ track: Track, autoplay: Bool, isFallback: Bool = false) {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        stallTask?.cancel()
        artworkTask?.cancel()

        if !isFallback {
            fallbackAttempts = 0
        }

        currentTrack = track
        currentTime = 0
        duration = max(0, track.duration)
        errorMessage = nil
        isBuffering = autoplay
        playbackIntent = autoplay

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.api.playableStream(for: track)
                try Task.checkCancellation()
                guard generation == self.loadGeneration else { return }

                let asset = AVURLAsset(
                    url: stream.url,
                    options: [
                        self.assetHeaderKey: stream.headers,
                        AVURLAssetPreferPreciseDurationAndTimingKey: true
                    ]
                )
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 15
                self.observe(item: item)
                self.player.replaceCurrentItem(with: item)
                self.duration = max(self.duration, track.duration)
                self.library.recordPlay(track)
                self.updateNowPlaying()
                self.loadArtwork(for: track, generation: generation)

                if autoplay {
                    self.activateAudioSession()
                    self.player.play()
                    self.isPlaying = true
                }
                if stream.isPreview {
                    self.showNotice("Для этого трека доступен только фрагмент")
                }
            } catch is CancellationError {
                return
            } catch let error as SoundCloudAPIError {
                guard generation == self.loadGeneration else { return }
                if error == .cancelled { return }
                await self.handlePlaybackFailure(error)
            } catch {
                guard generation == self.loadGeneration else { return }
                await self.handlePlaybackFailure(.network(error.localizedDescription))
            }
        }
    }

    private func observe(item: AVPlayerItem) {
        itemCancellables.removeAll()
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                Task { @MainActor in
                    switch status {
                    case .readyToPlay:
                        self.isBuffering = false
                        let itemDuration = item.duration.seconds
                        if itemDuration.isFinite, itemDuration > 0 {
                            self.duration = itemDuration
                        }
                        self.updateNowPlaying()
                    case .failed:
                        let message = item.error?.localizedDescription ?? "Поток прервался"
                        await self.handlePlaybackFailure(.network(message))
                    default:
                        break
                    }
                }
            }
            .store(in: &itemCancellables)
    }

    private func configurePlayerObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = max(0, seconds)
                }
                self.updateNowPlaying()
            }
        }

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                Task { @MainActor in
                    self.handleTimeControl(status)
                }
            }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let item = notification.object as? AVPlayerItem,
                  item === self.player.currentItem else { return }
            Task { @MainActor in self.handleEnded() }
        })

        notificationObservers.append(center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handlePlaybackFailure(.noStream)
            }
        })

        notificationObservers.append(center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleStall() }
        })
    }

    private func handleTimeControl(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isPlaying = true
            isBuffering = false
            stallTask?.cancel()
        case .waitingToPlayAtSpecifiedRate:
            if playbackIntent {
                isPlaying = true
                isBuffering = true
                scheduleStallRecovery()
            }
        case .paused:
            if !playbackIntent {
                isPlaying = false
            }
            isBuffering = false
        @unknown default:
            break
        }
        updateNowPlaying()
    }

    private func handleEnded() {
        if repeatMode == .one {
            seek(to: 0)
            play()
            return
        }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            loadAndPlay(queue[currentIndex], autoplay: true)
            return
        }
        if repeatMode == .all, !queue.isEmpty {
            currentIndex = 0
            loadAndPlay(queue[0], autoplay: true)
            return
        }
        playbackIntent = false
        isPlaying = false
        currentTime = duration
        updateNowPlaying()
    }

    private func handleStall() {
        guard playbackIntent else { return }
        isBuffering = true
        scheduleStallRecovery()
    }

    private func scheduleStallRecovery() {
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.playbackIntent, self.player.timeControlStatus != .playing else { return }
            await self.handlePlaybackFailure(.network("Поток остановился"))
        }
    }

    private func handlePlaybackFailure(_ error: SoundCloudAPIError) async {
        if error.requiresCredentialsFix {
            playbackIntent = false
            isPlaying = false
            isBuffering = false
            errorMessage = error.errorDescription
            return
        }

        guard let currentTrack else { return }
        if fallbackAttempts >= 2 {
            errorMessage = error.errorDescription
            advanceAfterFailure()
            return
        }

        fallbackAttempts += 1
        let message: String
        if case .regionBlocked = error {
            message = "Трек недоступен в регионе. Ищу замену…"
        } else if case .noStream = error {
            message = "Нет доступного потока. Ищу замену…"
        } else {
            message = "Трек прервался. Включаю похожий…"
        }
        showNotice(message)

        var excluded = Set(queue.map(\.id))
        excluded.insert(currentTrack.id)
        if let replacement = await fallbackProvider?(excluded) {
            if queue.indices.contains(currentIndex) {
                queue[currentIndex] = replacement
            } else {
                queue.append(replacement)
            }
            loadAndPlay(replacement, autoplay: true, isFallback: true)
        } else {
            errorMessage = error.errorDescription
            advanceAfterFailure()
        }
    }

    private func advanceAfterFailure() {
        isBuffering = false
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            loadAndPlay(queue[currentIndex], autoplay: true, isFallback: true)
        } else if repeatMode == .all, !queue.isEmpty {
            currentIndex = 0
            loadAndPlay(queue[0], autoplay: true, isFallback: true)
        } else {
            playbackIntent = false
            isPlaying = false
            updateNowPlaying()
        }
    }

    // MARK: - Audio session and interruptions

    private func configureAudioSessionObservers() {
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        })

        notificationObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
        })
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            AppLog.debug("Audio session activation failed: \(error.localizedDescription)")
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = playbackIntent
            pause()
        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if wasPlayingBeforeInterruption, options.contains(.shouldResume) {
                play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    // MARK: - Now playing and artwork

    private func updateNowPlaying() {
        nowPlaying.update(
            track: currentTrack,
            elapsed: currentTime,
            duration: duration,
            rate: Double(player.rate),
            isPlaying: isPlaying,
            queueIndex: currentIndex,
            queueCount: queue.count
        )
    }

    private func loadArtwork(for track: Track, generation: Int) {
        artworkTask?.cancel()
        let trackID = track.id
        let url = track.artworkURL
        artworkTask = Task { [weak self] in
            let image = await ArtworkCache.shared.image(for: url)
            guard !Task.isCancelled, let self, generation == self.loadGeneration,
                  self.currentTrack?.id == trackID else { return }
            self.nowPlaying.updateArtwork(image)
        }
    }

    private func showNotice(_ text: String) {
        noticeTask?.cancel()
        notice = text
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.notice == text {
                self.notice = nil
            }
        }
    }

    // MARK: - NowPlayingDelegate

    func remotePlay() { play() }
    func remotePause() { pause() }
    func remoteToggle() { togglePlayPause() }
    func remoteNext() { next() }
    func remotePrevious() { previous() }
    func remoteSeek(to time: TimeInterval) { seek(to: time) }
    func remoteSkipForward(_ interval: TimeInterval) { seek(by: interval) }
    func remoteSkipBackward(_ interval: TimeInterval) { seek(by: -interval) }
    func remoteToggleLike() { toggleLikeCurrent() }
}
