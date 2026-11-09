import Foundation

/// Keyless catalog for the free mode.
///
/// Uses the official Deezer public API (no registration, no key) and plays the
/// official 30-second previews that Deezer exposes for every track. It is a
/// deliberate fallback: SoundCloud stays the primary source and takes over as
/// soon as credentials are configured.
///
/// Nothing here circumvents DRM or uses unofficial endpoints: search, artist
/// pages and preview URLs are all part of the documented public API.
actor PreviewCatalog {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let baseURL = URL(string: "https://api.deezer.com")!
    private var lastRequestAt = Date.distantPast

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 40
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Public API (same shapes as SoundCloudAPIClient)

    func validate() async throws {
        _ = try await searchTracks(query: "phonk", limit: 1)
    }

    func searchTracks(query: String, limit: Int) async throws -> TrackPage {
        let url = try makeURL(
            path: "search/track",
            queryItems: [
                ("q", query),
                ("limit", String(min(max(limit, 1), 100)))
            ]
        )
        let response: ListResponse<TrackDTO> = try await getList(url: url)
        return mapTracks(response)
    }

    func searchArtists(query: String, limit: Int) async throws -> ArtistPage {
        let url = try makeURL(
            path: "search/artist",
            queryItems: [
                ("q", query),
                ("limit", String(min(max(limit, 1), 100)))
            ]
        )
        let response: ListResponse<ArtistDTO> = try await getList(url: url)
        return ArtistPage(
            artists: response.data.compactMap(mapArtist),
            nextHref: response.next.flatMap(URL.init(string:))
        )
    }

    func artistTop(artistID: String, limit: Int) async throws -> TrackPage {
        let url = try makeURL(
            path: "artist/\(try encoded(artistID))/top",
            queryItems: [("limit", String(min(max(limit, 1), 100)))]
        )
        let response: ListResponse<TrackDTO> = try await getList(url: url)
        return mapTracks(response)
    }

    func relatedArtists(artistID: String, limit: Int) async throws -> ArtistPage {
        let url = try makeURL(
            path: "artist/\(try encoded(artistID))/related",
            queryItems: [("limit", String(min(max(limit, 1), 100)))]
        )
        let response: ListResponse<ArtistDTO> = try await getList(url: url)
        return ArtistPage(
            artists: response.data.compactMap(mapArtist),
            nextHref: response.next.flatMap(URL.init(string:))
        )
    }

    func trackPage(nextHref: URL) async throws -> TrackPage {
        let response: ListResponse<TrackDTO> = try await getList(url: try validated(nextHref))
        return mapTracks(response)
    }

    func artistPage(nextHref: URL) async throws -> ArtistPage {
        let response: ListResponse<ArtistDTO> = try await getList(url: try validated(nextHref))
        return ArtistPage(
            artists: response.data.compactMap(mapArtist),
            nextHref: response.next.flatMap(URL.init(string:))
        )
    }

    func stream(for track: Track) async throws -> PlayableStream {
        guard let numericID = track.numericID ?? Self.numericID(from: track.id) else {
            throw SoundCloudAPIError.noStream
        }
        let url = try makeURL(path: "track/\(numericID)", queryItems: [])
        let dto: TrackDTO = try await getItem(url: url)
        guard let preview = dto.preview.flatMap(URL.init(string:)) else {
            throw SoundCloudAPIError.noStream
        }
        return PlayableStream(url: preview, headers: [:], isPreview: true)
    }

    // MARK: - Mapping

    private func mapTracks(_ response: ListResponse<TrackDTO>) -> TrackPage {
        TrackPage(
            tracks: response.data.compactMap(mapTrack),
            nextHref: response.next.flatMap(URL.init(string:))
        )
    }

    private func mapTrack(_ dto: TrackDTO) -> Track? {
        guard let title = dto.title?.trimmed, !title.isEmpty,
              dto.preview != nil,
              dto.readable != false else {
            return nil
        }

        let artwork = (dto.album?.coverBig ?? dto.album?.coverMedium).flatMap(URL.init(string:))
            ?? (dto.artist?.pictureBig ?? dto.artist?.pictureMedium).flatMap(URL.init(string:))

        return Track(
            id: "deezer:track:\(dto.id)",
            numericID: dto.id,
            urn: nil,
            title: title,
            artist: dto.artist?.name?.nilIfBlank ?? "Deezer",
            artistID: dto.artist?.id.map { "deezer:artist:\($0)" },
            artworkURL: artwork,
            duration: TimeInterval(max(0, dto.duration ?? 30)),
            genre: "",
            license: "all-rights-reserved",
            permalinkURL: dto.link.flatMap(URL.init(string:)),
            access: .preview,
            createdAt: nil,
            playbackCount: 0,
            tags: [],
            isDownloadable: false,
            availableCountryCodes: [],
            isRegionCompatible: true
        )
    }

    private func mapArtist(_ dto: ArtistDTO) -> Artist? {
        guard let name = dto.name?.trimmed, !name.isEmpty else { return nil }
        return Artist(
            id: "deezer:artist:\(dto.id ?? 0)",
            numericID: dto.id,
            urn: nil,
            username: name,
            avatarURL: (dto.pictureBig ?? dto.pictureMedium).flatMap(URL.init(string:)),
            permalinkURL: dto.link.flatMap(URL.init(string:)),
            followersCount: max(0, dto.followers ?? 0),
            trackCount: max(0, dto.albums ?? 0),
            city: nil,
            country: nil
        )
    }

    private static func numericID(from value: String) -> Int? {
        guard let last = value.split(separator: ":").last else { return nil }
        return Int(last)
    }

    // MARK: - Networking

    private func getList<Item: Decodable>(url: URL) async throws -> ListResponse<Item> {
        let data = try await getData(url)
        do {
            return try decoder.decode(ListResponse<Item>.self, from: data)
        } catch {
            throw mappedDecodingError(data, error)
        }
    }

    private func getItem<Item: Decodable>(url: URL) async throws -> Item {
        let data = try await getData(url)
        do {
            return try decoder.decode(Item.self, from: data)
        } catch {
            throw mappedDecodingError(data, error)
        }
    }

    private func getData(_ url: URL) async throws -> Data {
        await throttle()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("Volna/1.0 (iOS; free preview mode)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SoundCloudAPIError.invalidResponse
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 404:
                throw SoundCloudAPIError.notFound
            case 429:
                throw SoundCloudAPIError.rateLimited(retryAfter: nil)
            case 401, 403:
                throw SoundCloudAPIError.forbidden(nil)
            default:
                throw SoundCloudAPIError.server(http.statusCode)
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

    private func mappedDecodingError(_ data: Data, _ error: Error) -> SoundCloudAPIError {
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
            if envelope.error.code == 4 {
                return .rateLimited(retryAfter: nil)
            }
            return .forbidden(envelope.error.message)
        }
        return .decoding(error.localizedDescription)
    }

    /// Deezer allows roughly 50 requests per 5 seconds; keep bursts gentle.
    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < 0.12 {
            try? await Task.sleep(nanoseconds: UInt64((0.12 - elapsed) * 1_000_000_000))
        }
        lastRequestAt = Date()
    }

    private func makeURL(path: String, queryItems: [(String, String)]) throws -> URL {
        guard let base = URL(string: "https://api.deezer.com/" + path),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw SoundCloudAPIError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty
            ? nil
            : queryItems.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else {
            throw SoundCloudAPIError.invalidResponse
        }
        return url
    }

    private func encoded(_ value: String) throws -> String {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw SoundCloudAPIError.invalidResponse
        }
        return encoded
    }

    private func validated(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "api.deezer.com" else {
            throw SoundCloudAPIError.invalidResponse
        }
        return url
    }

    // MARK: - DTOs

    private struct ListResponse<Item: Decodable>: Decodable {
        let data: [Item]
        let next: String?
    }

    private struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let message: String?
            let code: Int?
        }
        let error: Payload
    }

    private struct TrackDTO: Decodable {
        let id: Int
        let title: String?
        let duration: Int?
        let preview: String?
        let link: String?
        let readable: Bool?
        let artist: ArtistDTO?
        let album: AlbumDTO?
    }

    private struct ArtistDTO: Decodable {
        let id: Int?
        let name: String?
        let pictureBig: String?
        let pictureMedium: String?
        let link: String?
        let followers: Int?
        let albums: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case link
            case pictureBig = "picture_big"
            case pictureMedium = "picture_medium"
            case followers = "nb_fan"
            case albums = "nb_album"
        }
    }

    private struct AlbumDTO: Decodable {
        let coverBig: String?
        let coverMedium: String?

        enum CodingKeys: String, CodingKey {
            case coverBig = "cover_big"
            case coverMedium = "cover_medium"
        }
    }
}
