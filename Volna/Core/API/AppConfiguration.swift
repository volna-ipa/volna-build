import Foundation

enum AppConfiguration {
    static let appName = "Volna"
    static let appTagline = "Твоя волна. Твой вкус."

    static let starterArtists = [
        "kishlak",
        "capsizeofficial",
        "sta2tika",
        "onda_andar"
    ]

    static let starterGenres = [
        "phonk",
        "drift",
        "rap",
        "trap"
    ]

    static let apiBaseURL = URL(string: "https://api.soundcloud.com")!
    static let authTokenURL = URL(string: "https://secure.soundcloud.com/oauth/token")!
    static let apiDocsURL = URL(string: "https://developers.soundcloud.com/docs/api/guide")!
    static let apiTermsURL = URL(string: "https://developers.soundcloud.com/docs/api/terms-of-use")!
    static let registerAppURL = URL(string: "https://soundcloud.com/you/apps")!
    static let widgetBaseURL = URL(string: "https://w.soundcloud.com/player/")!

    static var clientIDFromBundle: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SoundCloudClientID") as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static var clientSecretFromBundle: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SoundCloudClientSecret") as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    /// Region reported by the device. SoundCloud still performs its own geo checks;
    /// this value is only an additional client-side guard.
    static var regionCode: String {
        if #available(iOS 16.0, *) {
            return Locale.current.region?.identifier.uppercased() ?? "RU"
        }
        return (Locale.current.regionCode ?? "RU").uppercased()
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    static var year: Int {
        Calendar(identifier: .gregorian).component(.year, from: Date())
    }
}
