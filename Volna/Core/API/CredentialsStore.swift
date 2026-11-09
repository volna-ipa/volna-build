import Foundation

struct AppCredentials: Codable, Equatable, Sendable {
    let clientID: String
    let clientSecret: String

    var isValid: Bool {
        !clientID.trimmed.isEmpty && !clientSecret.trimmed.isEmpty
    }

    var maskedClientID: String {
        guard clientID.count > 8 else { return "••••" }
        return String(clientID.prefix(4)) + "…" + String(clientID.suffix(4))
    }
}

struct CredentialsStore: Sendable {
    private let keychain: KeychainStore
    private let credentialsAccount = "soundcloud.credentials"

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func load() -> AppCredentials? {
        if let data = keychain.read(account: credentialsAccount),
           let stored = try? JSONDecoder().decode(AppCredentials.self, from: data),
           stored.isValid {
            return stored
        }
        return bundledCredentials()
    }

    func loadUserCredentials() -> AppCredentials? {
        guard let data = keychain.read(account: credentialsAccount),
              let stored = try? JSONDecoder().decode(AppCredentials.self, from: data),
              stored.isValid else {
            return nil
        }
        return stored
    }

    func bundledCredentials() -> AppCredentials? {
        guard let id = AppConfiguration.clientIDFromBundle,
              let secret = AppConfiguration.clientSecretFromBundle else {
            return nil
        }
        let credentials = AppCredentials(clientID: id, clientSecret: secret)
        return credentials.isValid ? credentials : nil
    }

    func save(_ credentials: AppCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.save(data, account: credentialsAccount)
    }

    func clearUserCredentials() {
        keychain.delete(account: credentialsAccount)
    }

    func hasUserCredentials() -> Bool {
        loadUserCredentials() != nil
    }
}
