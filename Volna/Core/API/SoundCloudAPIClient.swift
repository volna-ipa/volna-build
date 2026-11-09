import Foundation

actor SoundCloudAPIClient {
    private let auth: SoundCloudAuthService
    /// Free, keyless fallback used only while no SoundCloud credentials exist.
    private let preview: PreviewCatalog?
    private let limiter: RateLimiter
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let region: String
    private var backoffUntil: Date?

    init(
        auth: SoundCloudAuthService,
        limiter: RateLimiter = RateLimiter(),
        session: URLSession? = nil,
        region: String = AppConfiguration.regionCode,
        preview: PreviewCatalog? = nil
    ) {
        self.auth = auth
        self.preview = preview
        self.limiter = limiter
        self.region = region.uppercased()

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = URLCache(
                memoryCapacity: 32 * 1024 * 1024,
                diskCapacity: 128 * 1024 * 1024,
                diskPath: "VolnaMetadata"
            )
            self.session = URLSession(configuration: configuration)
        }
    }

    func validateConnection() async throws {
        if await usesPreview(), let preview {
            try await preview.validate()
            return
        }
        _ = try await auth.accessToken(forceRefresh: false)
        _ = try await searchTracksPage(query: "phonk", genre: nil, limit: 1)
    }

    /// True when SoundCloud keys are absent and the free preview catalog is available.
    private func usesPreview() async -> Bool {
        guard preview != nil else { return false }
        let configured = await auth.hasCredentials()
        return !configured
    }

    func searchTracksPage(query: String?, genre: String? = nil, limit: Int = 40) async throws -> TrackPage {
        if await usesPreview(), let preview {
            let value = (query ?? genre ?? "").trimmed
            guard !value.isEmpty else { throw SoundCloudAPIError.noResults }
            return try await preview.searchTracks(query: value, limit: limit)
        }
        var items = [
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "access", value: "playable"),
            URLQueryItem(name: "linked_partitioning", value: "true")
        ]

        if let query = query?.trimmed, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        } else if let genre = genre?.trimmed, !genre.isEmpty {
            items.append(URLQueryItem(name: "q", value: genre))
        }

        if let genre = genre?.trimmed, !genre.isEmpty {
            items.append(URLQueryItem(name: "genres", value: genre))
        }

        let url = try makeURL(path: "tracks", queryItems: items)
        return try await fetchTrackPage(url: url, category: .search)
    }

    func tracksPage(nextHref: URL) async throws -> TrackPage {
        if await usesPreview(), let preview {
            return try await preview.trackPage(nextHref: nextHref)
        }
        return try await fetchTrackPage(url: try validated(nextHref), category: .search)
    }

    func searchArtistsPage(query: String, limit: Int = 20) async throws -> ArtistPage {
        if await usesPreview(), let preview {
            return try await preview.searchArtists(query: query, limit: limit)
        }
        let url = try makeURL(path: "users", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "linked_partitioning", value: "true")
        ])
        return try await fetchArtistPage(url: url, category: .search)
    }

    func artistTracksPage(artistID: String, nextHref: URL? = nil, limit: Int = 30) async throws -> TrackPage {
        if await usesPreview(), let preview {
            if let nextHref {
                return try await preview.trackPage(nextHref: nextHref)
            }
            return try await preview.artistTop(artistID: artistID, limit: limit)
        }
        if let nextHref {
            return try await fetchTrackPage(url: try validated(nextHref), category: .general)
        }
        let url = try makeURL(path: "users/\(try encodedPathComponent(artistID))/tracks", queryItems: [
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "access", value: "playable"),
            URLQueryItem(name: "linked_partitioning", value: "true")
        ])
        return try await fetchTrackPage(url: url, category: .general)
    }

    func relatedArtistsPage(artistID: String, nextHref: URL? = nil, limit: Int = 20) async throws -> ArtistPage {
        if await usesPreview(), let preview {
            if let nextHref {
                return try await preview.artistPage(nextHref: nextHref)
            }
            return try await preview.relatedArtists(artistID: artistID, limit: limit)
        }
        if let nextHref {
            return try await fetchArtistPage(url: try validated(nextHref), category: .general)
        }
        let url = try makeURL(path: "users/\(try encodedPathComponent(artistID))/related", queryItems: [
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "linked_partitioning", value: "true")
        ])
        return try await fetchArtistPage(url: url, category: .general)
    }

    func relatedTracksPage(trackID: String, limit: Int = 20) async throws -> TrackPage {
        if await usesPreview() {
            // The free catalog has no "related tracks" endpoint; the engine
            // simply continues with artist pages and genre searches.
            return TrackPage(tracks: [], nextHref: nil)
        }
        let url = try makeURL(path: "tracks/\(try encodedPathComponent(trackID))/related", queryItems: [
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "access", value: "playable"),
            URLQueryItem(name: "linked_partitioning", value: "true")
        ])
        return try await fetchTrackPage(url: url, category: .general)
    }

    func streamDescriptor(for track: Track) async throws -> StreamDescriptor {
        guard track.access != .blocked, track.isRegionCompatible else {
            throw SoundCloudAPIError.regionBlocked
        }
        let resourceID = track.numericID.map(String.init) ?? track.id
        let url = try makeURL(path: "tracks/\(try encodedPathComponent(resourceID))/streams", queryItems: [])
        let dto: SCStreamsDTO = try await get(url: url, category: .stream)
        let descriptor = StreamDescriptor(
            hlsAAC160URL: dto.hlsAAC160URL.flatMap(URL.init(string:)),
            hlsMP3URL: dto.hlsMP3URL.flatMap(URL.init(string:)),
            previewMP3URL: dto.previewMP3URL.flatMap(URL.init(string:))
        )
        guard descriptor.bestURL != nil else {
            throw SoundCloudAPIError.noStream
        }
        return descriptor
    }

    func playableStream(for track: Track) async throws -> PlayableStream {
        if await usesPreview(), let preview {
            return try await preview.stream(for: track)
        }
        let descriptor = try await streamDescriptor(for: track)
        guard let url = descriptor.bestURL else {
            throw SoundCloudAPIError.noStream
        }
        let token = try await auth.accessToken()
        return PlayableStream(
            url: url,
            headers: ["Authorization": "OAuth \(token)"],
            isPreview: descriptor.isPreviewOnly
        )
    }

    private func fetchTrackPage(url: URL, category: RequestCategory) async throws -> TrackPage {
        let page: SCPage<SCTrackDTO> = try await fetchPage(url: url, category: category)
        let mapped = page.collection.compactMap { SCMapper.track(from: $0, region: region) }
            .filter { !$0.isBlocked }
        return TrackPage(tracks: mapped, nextHref: page.nextHref.flatMap(resolveNextHref))
    }

    private func fetchArtistPage(url: URL, category: RequestCategory) async throws -> ArtistPage {
        let page: SCPage<SCUserDTO> = try await fetchPage(url: url, category: category)
        let mapped = page.collection.compactMap(SCMapper.artist(from:))
        return ArtistPage(artists: mapped, nextHref: page.nextHref.flatMap(resolveNextHref))
    }

    private func fetchPage<Item: Decodable>(url: URL, category: RequestCategory) async throws -> SCPage<Item> {
        let data = try await getData(url: url, category: category)
        do {
            return try decoder.decode(SCPage<Item>.self, from: data)
        } catch {
            if let array = try? decoder.decode([Item].self, from: data) {
                return SCPage(collection: array, nextHref: nil)
            }
            throw SoundCloudAPIError.decoding(error.localizedDescription)
        }
    }

    private func get<Response: Decodable>(url: URL, category: RequestCategory) async throws -> Response {
        let data = try await getData(url: url, category: category)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SoundCloudAPIError.decoding(error.localizedDescription)
        }
    }

    private func getData(url: URL, category: RequestCategory) async throws -> Data {
        try await waitForBackoff()
        try await limiter.acquire(category)
        let token: String
        do {
            token = try await auth.accessToken()
        } catch let error as SoundCloudAPIError {
            throw error
        } catch {
            throw SoundCloudAPIError.network(error.localizedDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("Volna/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")

        var authRetryUsed = false
        var rateRetryCount = 0
        var serverRetryCount = 0

        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw SoundCloudAPIError.invalidResponse
                }

                if (200..<300).contains(http.statusCode) {
                    return data
                }

                let apiMessage = (try? decoder.decode(SCErrorDTO.self, from: data))?.bestMessage

                switch http.statusCode {
                case 401 where !authRetryUsed:
                    authRetryUsed = true
                    await auth.invalidateAccessToken()
                    let newToken = try await auth.accessToken()
                    request.setValue("OAuth \(newToken)", forHTTPHeaderField: "Authorization")
                    try await limiter.acquire(category)
                    continue

                case 401:
                    throw SoundCloudAPIError.invalidCredentials

                case 429:
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 30
                    let wait = max(1, retryAfter)
                    backoffUntil = Date().addingTimeInterval(wait)
                    if rateRetryCount >= 2 {
                        throw SoundCloudAPIError.rateLimited(retryAfter: wait)
                    }
                    rateRetryCount += 1
                    try await Task.sleep(nanoseconds: UInt64(min(wait, 60) * 1_000_000_000))
                    try await limiter.acquire(category)
                    continue

                case 500...599:
                    if serverRetryCount < 2 {
                        serverRetryCount += 1
                        let wait = Double(serverRetryCount) * 1.2
                        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                        try await limiter.acquire(.general)
                        continue
                    }
                    throw SoundCloudAPIError.server(http.statusCode)

                default:
                    throw SoundCloudAPIError.status(http.statusCode, message: apiMessage)
                }
            } catch let error as SoundCloudAPIError {
                throw error
            } catch let error as URLError {
                if error.code == .cancelled { throw SoundCloudAPIError.cancelled }
                throw SoundCloudAPIError.network(error.localizedDescription)
            } catch is CancellationError {
                throw SoundCloudAPIError.cancelled
            } catch {
                throw SoundCloudAPIError.network(error.localizedDescription)
            }
        }
    }

    private func waitForBackoff() async throws {
        guard let backoffUntil else { return }
        let interval = backoffUntil.timeIntervalSinceNow
        if interval > 0 {
            try await Task.sleep(nanoseconds: UInt64(min(interval, 60) * 1_000_000_000))
        }
        self.backoffUntil = nil
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let base = AppConfiguration.apiBaseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw SoundCloudAPIError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw SoundCloudAPIError.invalidResponse
        }
        return url
    }

    private func encodedPathComponent(_ value: String) throws -> String {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw SoundCloudAPIError.invalidResponse
        }
        return encoded
    }

    private func resolveNextHref(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return validatedURL(url)
        }
        return URL(string: value, relativeTo: AppConfiguration.apiBaseURL).flatMap(validatedURL)
    }

    private func validated(_ url: URL) throws -> URL {
        guard let validatedURL = validatedURL(url) else {
            throw SoundCloudAPIError.invalidResponse
        }
        return validatedURL
    }

    private func validatedURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "api.soundcloud.com" || host == "api-v2.soundcloud.com" else {
            return nil
        }
        return url
    }
}
