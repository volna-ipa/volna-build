import Foundation

enum SoundCloudAPIError: LocalizedError, Equatable {
    case notConfigured
    case invalidCredentials
    case unauthorized
    case forbidden(String?)
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case server(Int)
    case invalidResponse
    case decoding(String)
    case network(String)
    case noStream
    case regionBlocked
    case noResults
    case keychain(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Нужны Client ID и Client Secret SoundCloud. Добавьте их в настройках."
        case .invalidCredentials:
            return "SoundCloud не принял ключи. Проверьте Client ID и Client Secret, а также доступ к API."
        case .unauthorized:
            return "Сессия SoundCloud истекла. Попробуйте обновить ключи в настройках."
        case .forbidden(let message):
            if let message, !message.isEmpty {
                return "SoundCloud ограничил доступ: \(message)"
            }
            return "SoundCloud ограничил доступ к этому запросу."
        case .notFound:
            return "SoundCloud не нашёл этот ресурс. Возможно, трек или артист удалён."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Лимит запросов SoundCloud. Повторите через \(Int(retryAfter.rounded(.up))) с."
            }
            return "Лимит запросов SoundCloud. Попробуйте чуть позже."
        case .server(let status):
            return "SoundCloud временно недоступен (код \(status))."
        case .invalidResponse:
            return "SoundCloud вернул неожиданный ответ."
        case .decoding:
            return "Не удалось разобрать ответ SoundCloud."
        case .network(let message):
            return "Сеть недоступна: \(message)"
        case .noStream:
            return "У трека нет доступного аудиопотока."
        case .regionBlocked:
            return "Трек недоступен в вашем регионе."
        case .noResults:
            return "Пока не нашлось подходящих треков. Попробуйте обновить ленту."
        case .keychain(let message):
            return "Не удалось сохранить ключи в Keychain: \(message)"
        case .cancelled:
            return "Запрос отменён."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .server, .network:
            return true
        default:
            return false
        }
    }

    var requiresCredentialsFix: Bool {
        switch self {
        case .notConfigured, .invalidCredentials, .unauthorized:
            return true
        default:
            return false
        }
    }

    static func status(_ code: Int, message: String? = nil) -> SoundCloudAPIError {
        switch code {
        case 401:
            return .invalidCredentials
        case 403:
            return .forbidden(message)
        case 404:
            return .notFound
        case 406:
            return .invalidResponse
        case 429:
            return .rateLimited(retryAfter: nil)
        case 500...599:
            return .server(code)
        default:
            return .server(code)
        }
    }
}
