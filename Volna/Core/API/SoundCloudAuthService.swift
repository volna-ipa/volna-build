import Foundation

actor SoundCloudAuthService {
    private let store: CredentialsStore
    private let keychain: KeychainStore
    private let session: URLSession
    private let tokenAccount = "soundcloud.token"

    private var credentials: AppCredentials?
    private var token: OAuthToken?
    private var refreshTask: Task<OAuthToken, Error>?

    init(credentials: AppCredentials?, store: CredentialsStore = CredentialsStore(), session: URLSession? = nil) {
        self.credentials = credentials
        self.store = store
        self.keychain = KeychainStore()
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    func configure(_ credentials: AppCredentials?) {
        self.credentials = credentials
        self.token = nil
        self.refreshTask?.cancel()
        self.refreshTask = nil
        if credentials == nil {
            keychain.delete(account: tokenAccount)
        }
    }

    func currentCredentials() -> AppCredentials? {
        credentials
    }

    func hasCredentials() -> Bool {
        credentials?.isValid == true
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let credentials, credentials.isValid else {
            throw SoundCloudAPIError.notConfigured
        }

        if !forceRefresh, let token, token.isValid {
            return token.accessToken
        }

        if let refreshTask {
            return try await refreshTask.value.accessToken
        }

        let cached = token ?? loadToken(for: credentials)
        let task = Task<OAuthToken, Error> {
            try await Self.obtainToken(credentials: credentials, cached: cached, session: self.session)
        }
        refreshTask = task

        do {
            let newToken = try await task.value
            self.token = newToken
            persist(newToken, for: credentials)
            refreshTask = nil
            return newToken.accessToken
        } catch {
            refreshTask = nil
            if case SoundCloudAPIError.invalidCredentials = error {
                keychain.delete(account: tokenAccount)
                self.token = nil
            }
            throw error
        }
    }

    /// Keeps the single-use refresh token but guarantees the next call exchanges it.
    func invalidateAccessToken() {
        guard let token else { return }
        self.token = OAuthToken(
            accessToken: "",
            refreshToken: token.refreshToken,
            expiresAt: Date.distantPast,
            scope: token.scope
        )
        if let credentials {
            persist(self.token!, for: credentials)
        }
    }

    func verifyConnection() async throws {
        _ = try await accessToken(forceRefresh: true)
    }

    private static func obtainToken(credentials: AppCredentials, cached: OAuthToken?, session: URLSession) async throws -> OAuthToken {
        if let refreshToken = cached?.refreshToken, !refreshToken.isEmpty {
            do {
                let response = try await requestToken(
                    parameters: [
                        "grant_type": "refresh_token",
                        "refresh_token": refreshToken,
                        "client_id": credentials.clientID,
                        "client_secret": credentials.clientSecret
                    ],
                    credentials: credentials,
                    useBasicAuth: false,
                    session: session
                )
                return makeToken(from: response, fallbackRefresh: refreshToken)
            } catch let error as SoundCloudAPIError {
                if case .network = error { throw error }
                if case .cancelled = error { throw error }
                // A used/expired refresh token is expected sometimes; fall back to a fresh app token.
            }
        }

        let response = try await requestToken(
            parameters: ["grant_type": "client_credentials"],
            credentials: credentials,
            useBasicAuth: true,
            session: session
        )
        return makeToken(from: response, fallbackRefresh: nil)
    }

    private static func makeToken(from response: OAuthTokenResponse, fallbackRefresh: String?) -> OAuthToken {
        let lifetime = TimeInterval(max(60, response.expiresIn ?? 3600))
        return OAuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? fallbackRefresh,
            expiresAt: Date().addingTimeInterval(lifetime - 90),
            scope: response.scope
        )
    }

    private static func requestToken(
        parameters: [String: String],
        credentials: AppCredentials,
        useBasicAuth: Bool,
        session: URLSession
    ) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: AppConfiguration.authTokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Volna/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        if useBasicAuth {
            let pair = "\(credentials.clientID):\(credentials.clientSecret)"
            let encoded = Data(pair.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = formBody(parameters)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SoundCloudAPIError.invalidResponse
            }

            if (200..<300).contains(http.statusCode) {
                do {
                    return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
                } catch {
                    throw SoundCloudAPIError.decoding("token: \(error.localizedDescription)")
                }
            }

            let apiMessage = (try? JSONDecoder().decode(SCErrorDTO.self, from: data))?.bestMessage
            switch http.statusCode {
            case 400, 401:
                throw SoundCloudAPIError.invalidCredentials
            case 403:
                throw SoundCloudAPIError.forbidden(apiMessage)
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw SoundCloudAPIError.rateLimited(retryAfter: retry)
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

    private static func formBody(_ parameters: [String: String]) -> Data {
        let pairs = parameters.map { key, value in
            "\(percentEncode(key))=\(percentEncode(value))"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func loadToken(for credentials: AppCredentials) -> OAuthToken? {
        guard let data = keychain.read(account: tokenAccount),
              let stored = try? JSONDecoder().decode(StoredOAuthToken.self, from: data),
              stored.clientID == credentials.clientID else {
            return nil
        }
        return stored.token
    }

    private func persist(_ token: OAuthToken, for credentials: AppCredentials) {
        let stored = StoredOAuthToken(clientID: credentials.clientID, token: token)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? keychain.save(data, account: tokenAccount)
    }
}
