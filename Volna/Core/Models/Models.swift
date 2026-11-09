import Foundation

enum TrackAccess: String, Codable, Sendable {
    case playable
    case preview
    case blocked
    case unknown
}

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let numericID: Int?
    let urn: String?
    let title: String
    let artist: String
    let artistID: String?
    let artworkURL: URL?
    let duration: TimeInterval
    let genre: String
    let license: String
    let permalinkURL: URL?
    let access: TrackAccess
    let createdAt: Date?
    let playbackCount: Int
    let tags: [String]
    let isDownloadable: Bool
    let availableCountryCodes: [String]
    let isRegionCompatible: Bool

    var isCreativeCommons: Bool {
        let value = license.lowercased()
        return value.hasPrefix("cc-") || value.contains("creative commons")
    }

    var isPreview: Bool {
        access == .preview
    }

    var isBlocked: Bool {
        access == .blocked || access == .unknown || !isRegionCompatible
    }

    var licenseLabel: String {
        if isCreativeCommons {
            return license.uppercased()
        }
        return "Все права защищены"
    }

    var genreLabel: String {
        genre.nilIfBlank ?? "Без жанра"
    }

    var yearLabel: String? {
        guard let createdAt else { return nil }
        let year = Calendar(identifier: .gregorian).component(.year, from: createdAt)
        return String(year)
    }

    var attribution: String {
        "\(artist) · источник SoundCloud"
    }
}

struct Artist: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let numericID: Int?
    let urn: String?
    let username: String
    let avatarURL: URL?
    let permalinkURL: URL?
    let followersCount: Int
    let trackCount: Int
    let city: String?
    let country: String?

    var handle: String {
        "@" + username.replacingOccurrences(of: " ", with: "")
    }
}

struct TrackPage: Sendable {
    let tracks: [Track]
    let nextHref: URL?
}

struct ArtistPage: Sendable {
    let artists: [Artist]
    let nextHref: URL?
}

enum MixKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case forYou
    case newInGenres

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou:
            return "Похоже на твоих артистов"
        case .newInGenres:
            return "Новинки в твоих жанрах"
        }
    }

    var shortTitle: String {
        switch self {
        case .forYou:
            return "Для тебя"
        case .newInGenres:
            return "Новинки"
        }
    }

    var subtitle: String {
        switch self {
        case .forYou:
            return "Соседи по звуку и related-артисты"
        case .newInGenres:
            return "Свежие треки из твоих жанров"
        }
    }

    var symbol: String {
        switch self {
        case .forYou:
            return "waveform.path.ecg"
        case .newInGenres:
            return "sparkles"
        }
    }
}

struct RecommendationReason: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case seed
        case similarArtist
        case relatedTrack
        case genre
        case fresh
    }

    let kind: Kind
    let text: String
    let source: String?
}

struct RecommendedTrack: Identifiable, Codable, Hashable, Sendable {
    let track: Track
    let reason: RecommendationReason
    let score: Double
    let depth: Int
    let mixes: Set<MixKind>

    var id: String { track.id }
}

struct TasteProfile: Codable, Equatable, Sendable {
    var artists: [String]
    var genres: [String]
    var updatedAt: Date

    static var starter: TasteProfile {
        TasteProfile(
            artists: AppConfiguration.starterArtists,
            genres: AppConfiguration.starterGenres,
            updatedAt: Date()
        )
    }

    var normalizedArtists: [String] {
        artists.map(\.trimmed).filter { !$0.isEmpty }.uniqued()
    }

    var normalizedGenres: [String] {
        genres.map(\.normalizedGenre).filter { !$0.isEmpty }.uniqued()
    }

    var cacheKey: String {
        "v1|" + normalizedArtists.map(\.handleKey).sorted().joined(separator: ",")
            + "|" + normalizedGenres.sorted().joined(separator: ",")
    }

    func hasSameTaste(as other: TasteProfile) -> Bool {
        Set(normalizedArtists.map(\.handleKey)) == Set(other.normalizedArtists.map(\.handleKey))
            && Set(normalizedGenres) == Set(other.normalizedGenres)
    }
}

struct TasteSignals: Sendable {
    var likedArtists: [String: Int] = [:]
    var historyArtists: [String: Int] = [:]
    var likedGenres: [String: Int] = [:]
    var heardTrackIDs: Set<String> = []

    static let empty = TasteSignals()

    var isEmpty: Bool {
        likedArtists.isEmpty && historyArtists.isEmpty && likedGenres.isEmpty && heardTrackIDs.isEmpty
    }

    func artistAffinity(_ artist: String) -> Double {
        let key = artist.handleKey
        let liked = Double(likedArtists[key] ?? 0)
        let heard = Double(historyArtists[key] ?? 0)
        return min(2.0, liked * 0.7 + heard * 0.15)
    }

    func genreAffinity(_ genre: String) -> Double {
        guard !genre.isEmpty else { return 0 }
        return min(1.2, Double(likedGenres[genre.normalizedGenre] ?? 0) * 0.35)
    }
}

struct StreamDescriptor {
    let hlsAAC160URL: URL?
    let hlsMP3URL: URL?
    let previewMP3URL: URL?

    var bestURL: URL? {
        hlsAAC160URL ?? hlsMP3URL ?? previewMP3URL
    }

    var isPreviewOnly: Bool {
        hlsAAC160URL == nil && hlsMP3URL == nil && previewMP3URL != nil
    }
}

struct PlayableStream {
    let url: URL
    let headers: [String: String]
    let isPreview: Bool
}

struct OAuthToken: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?

    var isValid: Bool {
        !accessToken.isEmpty && expiresAt.timeIntervalSinceNow > 30
    }
}

struct StoredOAuthToken: Codable, Sendable {
    let clientID: String
    var token: OAuthToken
}
