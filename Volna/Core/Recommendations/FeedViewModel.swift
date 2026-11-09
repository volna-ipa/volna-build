import Foundation
import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    enum Source: Equatable {
        case none
        case cache
        case live
    }

    @Published private(set) var items: [RecommendedTrack] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var source: Source = .none
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var hasMore = true

    private let engine: RecommendationEngine
    private let cache: FeedCache
    private var profile = TasteProfile.starter
    private var signals = TasteSignals.empty
    private var started = false
    private var generation = 0
    private let pageSize = 22

    init(api: SoundCloudAPIClient, cache: FeedCache = .shared) {
        self.engine = RecommendationEngine(api: api)
        self.cache = cache
    }

    func start(profile: TasteProfile, signals: TasteSignals, force: Bool = false) async {
        let normalized = TasteProfile(
            artists: profile.normalizedArtists,
            genres: profile.normalizedGenres,
            updatedAt: profile.updatedAt
        )

        if started && !force && self.profile.hasSameTaste(as: normalized) {
            return
        }

        self.profile = normalized
        self.signals = signals
        started = true
        generation += 1
        let currentGeneration = generation

        if items.isEmpty {
            if let snapshot = await cache.load(), snapshot.fingerprint == normalized.cacheKey {
                items = snapshot.items
                source = .cache
                lastUpdated = snapshot.savedAt
                hasMore = true
            }
        }

        let isStale = lastUpdated.map { Date().timeIntervalSince($0) > 30 * 60 } ?? true
        if force || items.isEmpty || isStale {
            await refreshInternal(generation: currentGeneration)
        }
    }

    func refresh(profile: TasteProfile, signals: TasteSignals) async {
        self.profile = TasteProfile(
            artists: profile.normalizedArtists,
            genres: profile.normalizedGenres,
            updatedAt: profile.updatedAt
        )
        self.signals = signals
        started = true
        generation += 1
        await refreshInternal(generation: generation)
    }

    private func refreshInternal(generation currentGeneration: Int) async {
        guard !isLoading else { return }
        isLoading = true
        // Always release the flag, including the early return when a newer
        // generation supersedes this one; otherwise refresh is blocked forever.
        defer { isLoading = false }
        errorMessage = nil

        do {
            try await engine.configure(profile: profile, signals: signals)
            let batch = try await engine.nextBatch(limit: 24)
            guard currentGeneration == generation else { return }
            items = batch
            source = .live
            lastUpdated = Date()
            hasMore = true
            errorMessage = nil
            await cache.save(fingerprint: profile.cacheKey, items: batch)
        } catch let error as SoundCloudAPIError {
            guard currentGeneration == generation else { return }
            errorMessage = error.errorDescription
        } catch {
            errorMessage = currentGeneration == generation ? error.localizedDescription : nil
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore, !items.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let currentGeneration = generation

        do {
            let batch = try await engine.nextBatch(limit: pageSize)
            guard currentGeneration == generation else { return }
            let existing = Set(items.map(\.id))
            let fresh = batch.filter { !existing.contains($0.id) }
            if fresh.isEmpty {
                hasMore = false
            } else {
                items.append(contentsOf: fresh)
                if items.count > 220 {
                    items = Array(items.prefix(220))
                }
                lastUpdated = Date()
                await cache.save(fingerprint: profile.cacheKey, items: items)
            }
        } catch let error as SoundCloudAPIError {
            guard currentGeneration == generation else { return }
            if case .noResults = error {
                hasMore = false
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            guard currentGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func updateSignals(_ signals: TasteSignals) {
        self.signals = signals
    }

    func fallbackTrack(excluding excludedIDs: Set<String>) async -> Track? {
        if let track = firstFallback(excluding: excludedIDs) {
            return track
        }
        if hasMore {
            await loadMore()
            if let track = firstFallback(excluding: excludedIDs) {
                return track
            }
        }
        await refresh(profile: profile, signals: signals)
        return firstFallback(excluding: excludedIDs)
    }

    private func firstFallback(excluding excludedIDs: Set<String>) -> Track? {
        let candidates = items.filter {
            !excludedIDs.contains($0.track.id) && !$0.track.isBlocked
        }
        // Prefer full tracks, but in the free preview mode every track is a
        // preview, so fall back to one rather than giving up on playback.
        return (candidates.first(where: { !$0.track.isPreview }) ?? candidates.first)?.track
    }

    func items(for mix: MixKind) -> [RecommendedTrack] {
        items.filter { $0.mixes.contains(mix) }
    }

    func reset() {
        items = []
        source = .none
        started = false
        hasMore = true
        lastUpdated = nil
        errorMessage = nil
    }
}
