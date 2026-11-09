# Проверка SoundCloud API

Скрипт `tools/check-soundcloud-api.ps1` проверяет доступность публичного API SoundCloud и валидность ключей приложения. Он ничего не публикует и не обходит ограничения — только официальные эндпоинты.

## Запуск

```powershell
powershell -ExecutionPolicy Bypass -File tools/check-soundcloud-api.ps1
```

Результат: `docs/soundcloud-api-report.json` (файл в `.gitignore`, потому что может содержать сведения о вашей учётной записи).

Ключи читаются по приоритету:

1. Параметры `-ClientId` / `-ClientSecret`.
2. Переменные окружения `SOUNDCLOUD_CLIENT_ID` / `SOUNDCLOUD_CLIENT_SECRET`.
3. `Config/Secrets.xcconfig`.

Секрет и OAuth-токены никогда не печатаются и не пишутся в отчёт.

## Что проверяется

| Проверка | Что означает |
|---|---|
| **OpenAPI specification** | `api.soundcloud.com` отвечает и отдаёт спецификацию API. |
| **Anonymous API search** | Анонимный поиск. Ожидаемый результат — `403`: с 2026 года нужен OAuth-токен. |
| **oEmbed (Web-embed fallback)** | `soundcloud.com/oembed` — официальный HTML-плеер без ключей. Может быть недоступен из некоторых сетей (в РФ часто блокируется). |
| **Widget host (Web-embed fallback)** | `w.soundcloud.com/player/api.js` — хост официального виджета. Если он доступен, Web-embed режим приложения работает даже при заблокированном `soundcloud.com`. |
| **OAuth client credentials** | Обмен `Client ID` + `Client Secret` на access token. Именно этот токен нужен для поиска и получения потоков. |

## Как получить ключи

С 2026 года регистрация API-приложения требует подписки **SoundCloud Artist Pro**.

1. Оформите Artist Pro на [checkout.soundcloud.com/artist/buy/artist-pro](https://checkout.soundcloud.com/artist/buy/artist-pro).
2. Создайте приложение одним из способов:
   - CLI (рекомендуется): команда со страницы [developers.soundcloud.com/docs/api/register-app](https://developers.soundcloud.com/docs/api/register-app) — она требует Node.js 18+ и подтверждения по pairing-ссылке;
   - вручную: [soundcloud.com/you/apps](https://soundcloud.com/you/apps) → *Register a new app*.
3. Скопируйте **Client ID** и **Client Secret**.

Куда их положить:

- локально в `Config/Secrets.xcconfig` (файл в `.gitignore`) — значения попадут в `Info.plist` при сборке;
- либо ввести прямо в приложении: **Профиль → SoundCloud → ключи** — они сохранятся в Keychain и не попадут в бандл.

## Текущий статус (2026-11-09)

- `OpenAPI specification` — OK.
- `Anonymous API search` — 403, как и ожидается без токена.
- `oEmbed` — предупреждение: `soundcloud.com` недоступен из этой сети.
- `Widget host` — OK, официальный виджет доступен.
- `OAuth client credentials` — предупреждение: ключи не заданы (`Config/Secrets.xcconfig` пуст).

Без `Client ID` + `Client Secret` приложение запускается, но лента и поиск не работают: SoundCloud не отдаёт результаты без OAuth-токена. Web-embed режим остаётся доступен для треков, открытых по прямой ссылке.

## Если проверка не проходит

| Симптом | Причина / решение |
|---|---|
| `OAuth client credentials` — warning | Не заполнены оба ключа. Нужны именно **оба**: ID и Secret. |
| `401` / `invalid_client` | Ключи неверны, приложение удалено или нет активной подписки Artist Pro. |
| `429` | Лимит запросов. Подождите и повторите; приложение учитывает `Retry-After`. |
| `oEmbed` — timeout | Сеть блокирует `soundcloud.com`; проверьте `Widget host`. Для плеера это не критично. |
| Все запросы `403` | Токен не передаётся или истёк. Проверьте, что в запросах есть заголовок `Authorization: OAuth <token>`. |
