import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var profile: TasteProfile {
        didSet { persistProfile() }
    }
    @Published var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Keys.theme) }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    private enum Keys {
        static let profile = "volna.taste.profile"
        static let theme = "volna.theme"
        static let onboarding = "volna.onboarding.completed"
        static let haptics = "volna.haptics"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.profile),
           let saved = try? decoder.decode(TasteProfile.self, from: data),
           !saved.artists.isEmpty || !saved.genres.isEmpty {
            profile = saved
        } else {
            profile = .starter
        }

        themeMode = ThemeMode(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .dark
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        if defaults.object(forKey: Keys.haptics) == nil {
            hapticsEnabled = true
        } else {
            hapticsEnabled = defaults.bool(forKey: Keys.haptics)
        }
    }

    func updateTaste(artists: [String], genres: [String]) {
        profile = TasteProfile(
            artists: artists.map(\.trimmed).filter { !$0.isEmpty }.uniqued(),
            genres: genres.map(\.normalizedGenre).filter { !$0.isEmpty }.uniqued(),
            updatedAt: Date()
        )
    }

    func addArtist(_ name: String) {
        let value = name.trimmed
        guard !value.isEmpty else { return }
        var artists = profile.normalizedArtists
        guard !artists.contains(where: { $0.handleKey == value.handleKey }) else { return }
        artists.append(value)
        updateTaste(artists: artists, genres: profile.normalizedGenres)
    }

    func removeArtist(_ name: String) {
        updateTaste(
            artists: profile.normalizedArtists.filter { $0.handleKey != name.handleKey },
            genres: profile.normalizedGenres
        )
    }

    func addGenre(_ name: String) {
        let value = name.normalizedGenre
        guard !value.isEmpty else { return }
        var genres = profile.normalizedGenres
        guard !genres.contains(value) else { return }
        genres.append(value)
        updateTaste(artists: profile.normalizedArtists, genres: genres)
    }

    func removeGenre(_ name: String) {
        updateTaste(
            artists: profile.normalizedArtists,
            genres: profile.normalizedGenres.filter { $0 != name.normalizedGenre }
        )
    }

    func resetTaste() {
        profile = .starter
    }

    private func persistProfile() {
        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: Keys.profile)
    }
}
