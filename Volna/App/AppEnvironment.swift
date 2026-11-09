import Foundation
import SwiftUI

enum ConnectionStatus: Equatable {
    case unknown
    case checking
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .unknown: return "Не проверено"
        case .checking: return "Проверяем…"
        case .connected: return "Подключено"
        case .failed: return "Нет соединения"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let settings: SettingsStore
    let library: LibraryStore
    let api: SoundCloudAPIClient
    let feed: FeedViewModel
    let player: PlaybackController
    let auth: SoundCloudAuthService

    @Published private(set) var hasCredentials: Bool
    @Published private(set) var isPreviewMode: Bool
    @Published private(set) var connectionStatus: ConnectionStatus = .unknown

    private let credentialsStore: CredentialsStore
    private var didBootstrap = false

    init() {
        let settings = SettingsStore()
        let credentialsStore = CredentialsStore()
        let credentials = credentialsStore.load()
        let auth = SoundCloudAuthService(credentials: credentials, store: credentialsStore)
        let preview = PreviewCatalog()
        let api = SoundCloudAPIClient(auth: auth, preview: preview)
        let library = LibraryStore()
        let player = PlaybackController(api: api, library: library)
        let feed = FeedViewModel(api: api)

        player.fallbackProvider = { [weak feed] excluded in
            await feed?.fallbackTrack(excluding: excluded)
        }

        self.settings = settings
        self.credentialsStore = credentialsStore
        self.auth = auth
        self.api = api
        self.library = library
        self.player = player
        self.feed = feed
        self.hasCredentials = credentials != nil
        self.isPreviewMode = credentials == nil
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        await verifyConnection()

        if settings.hasCompletedOnboarding, connectionStatus.isConnected {
            await startFeedIfNeeded()
        }
    }

    func verifyConnection() async {
        connectionStatus = .checking
        do {
            try await api.validateConnection()
            connectionStatus = .connected
        } catch let error as SoundCloudAPIError {
            connectionStatus = .failed(error.errorDescription ?? "Не удалось подключиться")
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    func saveCredentials(clientID: String, clientSecret: String) async throws {
        let credentials = AppCredentials(
            clientID: clientID.trimmed,
            clientSecret: clientSecret.trimmed
        )
        guard credentials.isValid else {
            throw SoundCloudAPIError.notConfigured
        }

        try credentialsStore.save(credentials)
        await auth.configure(credentials)
        hasCredentials = true
        isPreviewMode = false
        feed.reset()
        connectionStatus = .checking

        do {
            try await api.validateConnection()
            connectionStatus = .connected
        } catch let error as SoundCloudAPIError {
            if error.requiresCredentialsFix {
                // Rejected keys would leave the app unusable; drop them and keep
                // working in the free preview mode until valid keys are entered.
                credentialsStore.clearUserCredentials()
                let fallback = credentialsStore.bundledCredentials()
                await auth.configure(fallback)
                hasCredentials = fallback != nil
                isPreviewMode = fallback == nil
                feed.reset()
            }
            connectionStatus = .failed(error.errorDescription ?? "Проверьте ключи")
            throw error
        }
    }

    func removeSavedCredentials() async {
        credentialsStore.clearUserCredentials()
        let fallback = credentialsStore.bundledCredentials()
        await auth.configure(fallback)
        hasCredentials = fallback != nil
        isPreviewMode = fallback == nil
        feed.reset()
        connectionStatus = hasCredentials ? .unknown : .failed("Ключи SoundCloud не добавлены. Работает бесплатный режим.")
    }

    func previewClientID() -> String? {
        credentialsStore.load()?.maskedClientID
    }

    func isUsingBundledCredentials() -> Bool {
        credentialsStore.loadUserCredentials() == nil && credentialsStore.bundledCredentials() != nil
    }

    func startFeedIfNeeded(force: Bool = false) async {
        guard settings.hasCompletedOnboarding else { return }
        await feed.start(
            profile: settings.profile,
            signals: library.signals(),
            force: force
        )
    }

    func refreshFeed() async {
        await feed.refresh(profile: settings.profile, signals: library.signals())
    }

    func updateTaste(artists: [String], genres: [String]) async {
        settings.updateTaste(artists: artists, genres: genres)
        feed.reset()
        if settings.hasCompletedOnboarding {
            await startFeedIfNeeded(force: true)
        }
    }

    func finishOnboarding() async {
        settings.hasCompletedOnboarding = true
        await verifyConnection()
        await startFeedIfNeeded(force: true)
    }

    func playFirstMix(_ kind: MixKind) {
        let tracks = feed.items(for: kind).map(\.track)
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks)
    }
}
