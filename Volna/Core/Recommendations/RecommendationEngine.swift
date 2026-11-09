import Foundation

/// Builds an endless, preference-weighted artist graph.
///
/// Seeds -> related artists (depth 1) -> their related artists (depth 2/3).
/// Every artist page and a sample of related tracks feed a ranked pool. When the
/// graph is exhausted, the engine rotates through the listener's genres.
actor RecommendationEngine {
    private struct ArtistNode {
        let artist: Artist
        let depth: Int
        let parentName: String?
        var nextHref: URL?
        var didRequestTracks = false
        var tracksExhausted = false
        var relatedLoaded = false
        var relatedTracksLoaded = false
        var lastUsed = Date.distantPast
        var weight: Double
    }

    private let api: SoundCloudAPIClient
    private let maxDepth = 3
    private let maxArtists = 64

    private var profile = TasteProfile.starter
    private var signals = TasteSignals.empty
    private var nodes: [String: ArtistNode] = [:]
    private var pending: [String: RecommendedTrack] = [:]
    private var seen: Set<String> = []
    private var genreNext: [String: URL] = [:]
    private var exhaustedGenres: Set<String> = []
    private var genreIndex = 0
    private var configured = false

    init(api: SoundCloudAPIClient) {
        self.api = api
    }

    func configure(profile: TasteProfile, signals: TasteSignals) async throws {
        self.profile = TasteProfile(
            artists: profile.normalizedArtists,
            genres: profile.normalizedGenres,
            updatedAt: profile.updatedAt
        )
        self.signals = signals
        nodes = [:]
        pending = [:]
        seen = []
        genreNext = [:]
        exhaustedGenres = []
        genreIndex = 0
        configured = false

        var lastError: SoundCloudAPIError?
        for seed in self.profile.normalizedArtists {
            do {
                let page = try await api.searchArtistsPage(query: seed, limit: 5)
                guard let artist = bestMatch(for: seed, in: page.artists) else { continue }
                addNode(
                    ArtistNode(
                        artist: artist,
                        depth: 0,
                        parentName: nil,
                        nextHref: nil,
                        weight: 1.0
                    )
                )
            } catch let error as SoundCloudAPIError {
                if error.requiresCredentialsFix { throw error }
                lastError = error
            } catch {
                lastError = .network(error.localizedDescription)
            }
        }

        configured = true
        if nodes.isEmpty, let lastError, self.profile.normalizedGenres.isEmpty {
            throw lastError
        }
    }

    func nextBatch(limit: Int = 24) async throws -> [RecommendedTrack] {
        guard configured else { throw SoundCloudAPIError.notConfigured }

        var lastError: SoundCloudAPIError?
        var attempts = 0
        while attempts < 10 {
            attempts += 1
            if pending.count >= limit { break }

            if let nodeID = chooseNode() {
                await expandRelatedIfNeeded(nodeID)
                do {
                    try await loadTracks(for: nodeID)
                } catch let error as SoundCloudAPIError {
                    if error.requiresCredentialsFix || error == .rateLimited(retryAfter: nil) {
                        throw error
                    }
                    lastError = error
                } catch {
                    lastError = .network(error.localizedDescription)
                }
            } else {
                do {
                    try await loadGenrePage()
                } catch let error as SoundCloudAPIError {
                    if error.requiresCredentialsFix { throw error }
                    lastError = error
                } catch {
                    lastError = .network(error.localizedDescription)
                }
            }
        }

        var result = drain(limit: limit)
        if result.isEmpty {
            do {
                try await loadGenrePage()
                result = drain(limit: limit)
            } catch let error as SoundCloudAPIError {
                lastError = error
            } catch {
                lastError = .network(error.localizedDescription)
            }
        }

        if result.isEmpty {
            throw lastError ?? SoundCloudAPIError.noResults
        }
        return result
    }

    private func bestMatch(for seed: String, in artists: [Artist]) -> Artist? {
        let key = seed.handleKey
        if let exact = artists.first(where: { $0.username.handleKey == key }) {
            return exact
        }
        // Only accept a clearly related username. Picking the first fuzzy result
        // would silently seed the feed with the wrong artist.
        return artists.first(where: {
            $0.username.handleKey.contains(key) || key.contains($0.username.handleKey)
        })
    }

    private func addNode(_ node: ArtistNode) {
        guard nodes[node.artist.id] == nil else { return }
        if node.depth > 0 && nodes.count >= maxArtists { return }
        nodes[node.artist.id] = node
    }

    private func chooseNode() -> String? {
        let now = Date()
        let available = nodes.values.filter { !$0.tracksExhausted }
        guard !available.isEmpty else { return nil }

        let chosen = available.max { lhs, rhs in
            nodeScore(lhs, now: now) < nodeScore(rhs, now: now)
        }
        guard var node = chosen else { return nil }
        node.lastUsed = now
        nodes[node.artist.id] = node
        return node.artist.id
    }

    private func nodeScore(_ node: ArtistNode, now: Date) -> Double {
        var score = node.weight
        if node.depth == 0 { score += 0.65 }
        score -= Double(node.depth) * 0.22
        score += signals.artistAffinity(node.artist.username)
        if !node.didRequestTracks { score += 0.8 }
        if node.nextHref != nil { score += 0.2 }
        let idle = now.timeIntervalSince(node.lastUsed)
        score += min(0.5, idle / 600.0)
        score += Double.random(in: 0...0.18)
        return score
    }

    private func expandRelatedIfNeeded(_ nodeID: String) async {
        guard var node = nodes[nodeID],
              !node.relatedLoaded,
              node.depth < maxDepth,
              let resourceID = artistResourceID(node.artist) else {
            return
        }
        node.relatedLoaded = true
        nodes[nodeID] = node

        do {
            let page = try await api.relatedArtistsPage(artistID: resourceID, limit: 12)
            for artist in page.artists {
                let affinity = signals.artistAffinity(artist.username)
                addNode(
                    ArtistNode(
                        artist: artist,
                        depth: node.depth + 1,
                        parentName: node.artist.username,
                        nextHref: nil,
                        weight: 0.55 + affinity
                    )
                )
            }
        } catch {
            // The artist may have no related page; the feed simply moves on.
        }
    }

    private func loadTracks(for nodeID: String) async throws {
        guard var node = nodes[nodeID],
              let resourceID = artistResourceID(node.artist) else {
            if var node = nodes[nodeID] {
                node.tracksExhausted = true
                nodes[nodeID] = node
            }
            return
        }

        let page: TrackPage
        if !node.didRequestTracks {
            page = try await api.artistTracksPage(artistID: resourceID, limit: 30)
            node.didRequestTracks = true
        } else if let nextHref = node.nextHref {
            page = try await api.artistTracksPage(artistID: resourceID, nextHref: nextHref, limit: 30)
        } else {
            node.tracksExhausted = true
            nodes[nodeID] = node
            return
        }

        node.nextHref = page.nextHref
        if page.nextHref == nil {
            node.tracksExhausted = true
        }
        nodes[nodeID] = node

        for track in page.tracks {
            incorporate(track: track, node: node, kind: node.depth == 0 ? .seed : (node.parentName == nil ? .similarArtist : .relatedTrack))
        }

        if !node.relatedTracksLoaded, node.depth <= 1, let first = page.tracks.first,
           let trackID = first.numericID.map(String.init) {
            node.relatedTracksLoaded = true
            nodes[nodeID] = node
            do {
                let related = try await api.relatedTracksPage(trackID: trackID, limit: 12)
                for track in related.tracks {
                    incorporate(
                        track: track,
                        node: node,
                        kind: .relatedTrack,
                        overrideSource: first.artist
                    )
                }
            } catch {
                // Related track discovery is a bonus, not a requirement.
            }
        }
    }

    private func incorporate(
        track: Track,
        node: ArtistNode,
        kind: RecommendationReason.Kind,
        overrideSource: String? = nil
    ) {
        guard !track.isBlocked,
              !signals.heardTrackIDs.contains(track.id),
              !seen.contains(track.id),
              pending[track.id] == nil else {
            return
        }

        let genre = track.genreLabel.lowercased()
        let profileGenres = Set(profile.normalizedGenres)
        let matchesGenre = !genre.isEmpty && (profileGenres.contains(genre)
            || track.tags.contains { profileGenres.contains($0.normalizedGenre) })
        let isFresh = track.createdAt.map { $0.timeIntervalSinceNow > -60 * 60 * 24 * 365 * 2 } ?? false
        let sourceName = overrideSource ?? node.parentName ?? node.artist.username

        var mixes: Set<MixKind> = [.forYou]
        if kind == .genre || matchesGenre || isFresh {
            mixes.insert(.newInGenres)
        }

        let reason: RecommendationReason
        if kind == .seed {
            reason = RecommendationReason(kind: .seed, text: "Твой артист · \(node.artist.username)", source: node.artist.username)
        } else if kind == .genre {
            reason = RecommendationReason(kind: .genre, text: "Новое в \(sourceName.lowercased())", source: sourceName)
        } else if kind == .relatedTrack {
            reason = RecommendationReason(kind: .relatedTrack, text: "Рядом с \(sourceName)", source: sourceName)
        } else {
            reason = RecommendationReason(kind: .similarArtist, text: "Похоже на \(sourceName)", source: sourceName)
        }

        var score = 1.0
        score -= Double(node.depth) * 0.18
        score += track.isCreativeCommons ? 0.45 : 0
        score += signals.artistAffinity(track.artist)
        score += signals.genreAffinity(track.genre)
        if matchesGenre { score += 0.4 }
        if isFresh { score += 0.15 }
        score += min(0.25, log(Double(track.playbackCount) + 1.0) / 30.0)
        if track.isPreview { score -= 0.8 }
        score += Double.random(in: 0...0.2)

        let recommendation = RecommendedTrack(
            track: track,
            reason: reason,
            score: score,
            depth: node.depth,
            mixes: mixes
        )
        pending[track.id] = recommendation

        if pending.count > 220 {
            let keep = pending.values.sorted { $0.score > $1.score }.prefix(180)
            pending = Dictionary(uniqueKeysWithValues: keep.map { ($0.track.id, $0) })
        }
    }

    private func loadGenrePage() async throws {
        var genres = profile.normalizedGenres
        if genres.isEmpty {
            genres = AppConfiguration.starterGenres
        }
        guard !genres.isEmpty else { throw SoundCloudAPIError.noResults }

        if exhaustedGenres.count >= genres.count {
            exhaustedGenres.removeAll()
        }

        var attempts = 0
        while attempts < genres.count {
            let genre = genres[genreIndex % genres.count]
            genreIndex += 1
            attempts += 1

            if exhaustedGenres.contains(genre) { continue }

            if let next = genreNext[genre] {
                let page = try await api.tracksPage(nextHref: next)
                absorbGenrePage(page, genre: genre)
                return
            }

            let page = try await api.searchTracksPage(query: genre, genre: nil, limit: 30)
            absorbGenrePage(page, genre: genre)
            return
        }

        throw SoundCloudAPIError.noResults
    }

    private func absorbGenrePage(_ page: TrackPage, genre: String) {
        if let next = page.nextHref {
            genreNext[genre] = next
        } else {
            genreNext.removeValue(forKey: genre)
            exhaustedGenres.insert(genre)
        }

        let template = ArtistNode(
            artist: Artist(
                id: "genre:\(genre)",
                numericID: nil,
                urn: nil,
                username: genre.capitalized,
                avatarURL: nil,
                permalinkURL: nil,
                followersCount: 0,
                trackCount: 0,
                city: nil,
                country: nil
            ),
            depth: 2,
            parentName: genre.capitalized,
            weight: 0.3
        )

        for track in page.tracks {
            incorporate(track: track, node: template, kind: .genre)
        }
    }

    private func drain(limit: Int) -> [RecommendedTrack] {
        let sorted = pending.values.sorted {
            if abs($0.score - $1.score) < 0.0001 {
                return $0.track.id < $1.track.id
            }
            return $0.score > $1.score
        }

        var result: [RecommendedTrack] = []
        for recommendation in sorted {
            guard !seen.contains(recommendation.track.id) else { continue }
            seen.insert(recommendation.track.id)
            pending.removeValue(forKey: recommendation.track.id)
            result.append(recommendation)
            if result.count >= limit { break }
        }
        return result
    }

    private func artistResourceID(_ artist: Artist) -> String? {
        if let numericID = artist.numericID { return String(numericID) }
        return SCMapper.numericID(from: artist.urn).map(String.init)
    }
}
