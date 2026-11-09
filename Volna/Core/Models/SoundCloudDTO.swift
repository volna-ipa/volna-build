import Foundation

/// A string that may arrive either as a comma-separated value or as an array.
struct SCStringList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            values = string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else if let array = try? container.decode([String].self) {
            values = array
        } else {
            values = []
        }
    }
}

struct SCPage<Item: Decodable>: Decodable {
    let collection: [Item]
    let nextHref: String?

    enum CodingKeys: String, CodingKey {
        case collection
        case nextHref = "next_href"
    }

    init(collection: [Item], nextHref: String?) {
        self.collection = collection
        self.nextHref = nextHref
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collection = try container.decodeIfPresent([Item].self, forKey: .collection) ?? []
        nextHref = try container.decodeIfPresent(String.self, forKey: .nextHref)
    }
}

struct SCUserDTO: Decodable {
    let id: Int?
    let urn: String?
    let username: String?
    let avatarURL: String?
    let permalinkURL: String?
    let followersCount: Int?
    let trackCount: Int?
    let city: String?
    let country: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case urn
        case username
        case avatarURL = "avatar_url"
        case permalinkURL = "permalink_url"
        case followersCount = "followers_count"
        case trackCount = "track_count"
        case city
        case country
        case description
    }
}

struct SCTrackDTO: Decodable {
    let id: Int?
    let urn: String?
    let title: String?
    let description: String?
    let artworkURL: String?
    let duration: Int?
    let genre: String?
    let license: String?
    let permalinkURL: String?
    let createdAt: String?
    let streamable: Bool?
    let access: String?
    let playbackCount: Int?
    let favoritingsCount: Int?
    let downloadable: Bool?
    let user: SCUserDTO?
    let metadataArtist: String?
    let availableCountryCodes: SCStringList?
    let tagList: SCStringList?
    let streamURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case urn
        case title
        case description
        case artworkURL = "artwork_url"
        case duration
        case genre
        case license
        case permalinkURL = "permalink_url"
        case createdAt = "created_at"
        case streamable
        case access
        case playbackCount = "playback_count"
        case favoritingsCount = "favoritings_count"
        case downloadable
        case user
        case metadataArtist = "metadata_artist"
        case availableCountryCodes = "available_country_codes"
        case tagList = "tag_list"
        case streamURL = "stream_url"
    }
}

struct SCStreamsDTO: Decodable {
    let hlsAAC160URL: String?
    let hlsMP3URL: String?
    let previewMP3URL: String?

    enum CodingKeys: String, CodingKey {
        case hlsAAC160URL = "hls_aac_160_url"
        case hlsMP3URL = "hls_mp3_128_url"
        case previewMP3URL = "preview_mp3_128_url"
    }
}

struct SCErrorDTO: Decodable {
    let message: String?
    let error: String?
    let errors: [SCErrorItemDTO]?

    var bestMessage: String? {
        if let message = message?.nilIfBlank { return message }
        if let error = error?.nilIfBlank { return error }
        return errors?.compactMap(\.errorMessage).first
    }
}

struct SCErrorItemDTO: Decodable {
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case errorMessage = "error_message"
    }
}

struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

enum SCDateParser {
    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = try? Date(string, strategy: .iso8601) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

enum SCMapper {
    static func track(from dto: SCTrackDTO, region: String) -> Track? {
        guard let title = dto.title?.trimmed, !title.isEmpty else { return nil }
        guard let stableID = stableTrackID(id: dto.id, urn: dto.urn) else { return nil }

        let numericID = dto.id ?? numericID(from: dto.urn)
        let accessRaw = dto.access?.lowercased()
        let access: TrackAccess
        if dto.streamable == false {
            access = .blocked
        } else if let accessRaw {
            access = TrackAccess(rawValue: accessRaw) ?? .playable
        } else {
            access = .playable
        }

        let tags = (dto.tagList?.values ?? []).map {
            $0.replacingOccurrences(of: "\"", with: "")
        }

        return Track(
            id: stableID,
            numericID: numericID,
            urn: dto.urn,
            title: title,
            artist: dto.metadataArtist?.nilIfBlank ?? dto.user?.username?.nilIfBlank ?? "SoundCloud",
            artistID: dto.user?.urn ?? dto.user?.id.map(String.init),
            artworkURL: dto.artworkURL.flatMap(URL.init(string:)),
            duration: TimeInterval(max(0, dto.duration ?? 0)) / 1000.0,
            genre: dto.genre?.trimmed ?? "",
            license: dto.license?.trimmed ?? "all-rights-reserved",
            permalinkURL: dto.permalinkURL.flatMap(URL.init(string:)),
            access: access,
            createdAt: SCDateParser.date(from: dto.createdAt),
            playbackCount: max(0, dto.playbackCount ?? 0),
            tags: tags,
            isDownloadable: dto.downloadable ?? false,
            availableCountryCodes: (dto.availableCountryCodes?.values ?? []).map { $0.uppercased() },
            isRegionCompatible: !isRegionBlocked(codes: dto.availableCountryCodes?.values ?? [], region: region)
        )
    }

    static func artist(from dto: SCUserDTO) -> Artist? {
        guard let username = dto.username?.trimmed, !username.isEmpty else { return nil }
        guard let stableID = stableUserID(id: dto.id, urn: dto.urn) else { return nil }
        return Artist(
            id: stableID,
            numericID: dto.id ?? numericID(from: dto.urn),
            urn: dto.urn,
            username: username,
            avatarURL: dto.avatarURL.flatMap(URL.init(string:)),
            permalinkURL: dto.permalinkURL.flatMap(URL.init(string:)),
            followersCount: max(0, dto.followersCount ?? 0),
            trackCount: max(0, dto.trackCount ?? 0),
            city: dto.city?.nilIfBlank,
            country: dto.country?.nilIfBlank
        )
    }

    private static func stableTrackID(id: Int?, urn: String?) -> String? {
        if let urn = urn?.nilIfBlank { return urn }
        if let id { return "soundcloud:tracks:\(id)" }
        return nil
    }

    private static func stableUserID(id: Int?, urn: String?) -> String? {
        if let urn = urn?.nilIfBlank { return urn }
        if let id { return "soundcloud:users:\(id)" }
        return nil
    }

    static func numericID(from urn: String?) -> Int? {
        guard let urn, let last = urn.split(separator: ":").last else { return nil }
        return Int(last)
    }

    private static func isRegionBlocked(codes: [String], region: String) -> Bool {
        let normalized = codes.map { $0.uppercased() }.filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return false }
        if normalized.contains("WW") || normalized.contains("WORLDWIDE") { return false }
        return !normalized.contains(region.uppercased())
    }
}
