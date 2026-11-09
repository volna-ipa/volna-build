# Volna

Нативное iOS-приложение (SwiftUI, минимум iOS 16) — музыкальный плеер с рекомендациями по вкусу на базе SoundCloud API. Личная сборка для sideload на iPhone.

## Статус проекта

| Компонент | Состояние |
|---|---|
| Исходный код | 37 Swift-файлов, ~0.5 МБ |
| Синтаксис Swift | проверен `swiftc -parse` (Swift 6.4.2, Windows) — без ошибок |
| Xcode-проект | сгенерирован: `Volna.xcodeproj` + shared scheme `Volna` |
| Сборка `.ipa` | **не выполнялась** — для iOS-сборки нужен macOS + Xcode или GitHub Actions |
| Музыка без ключей | **работает**: Deezer public API, официальные 30-сек превью |
| SoundCloud API | подключается опционально; для ключей нужна подписка Artist Pro |
| Документация | README + `docs/BUILD-AND-SIDELOAD.md` + `docs/STATUS.md` + `docs/SOUNDCLOUD_API_CHECK.md` |
| CI | `.github/workflows/build-ipa.yml` — сборка unsigned IPA на macOS-раннере |

## Возможности

- Работает **без ключей**: лента и поиск через официальный Deezer API, воспроизведение официальных 30-секундных превью.
- С ключами SoundCloud автоматически переключается на полные треки, related-артистов и related-треки.
- Бесконечная лента рекомендаций: стартовые артисты (kishlak, capsizeofficial, sta2tika, onda_andar) → related-артисты и треки (2–3 уровня).
- Плеер: play/pause, next/prev, seek, shuffle, repeat, очередь.
- Фоновое воспроизведение, экран блокировки и AirPods (`AVAudioSession`, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`).
- Фильтрация недоступных треков (нет streaming URL / региональная блокировка) с автоподстановкой похожего трека.
- Библиотека: лайки, история, плейлисты, локальное хранилище (Core Data), кэш обложек.
- Онбординг с выбором вкуса, поиск, настройки, Web-embed fallback.
- Тёмная/светлая тема, крупные обложки, минималистичный дизайн.

## Требования

- iPhone с iOS 16+ и кабель.
- Бесплатный Apple ID (для Sideloadly) **или** Mac с Xcode 15+.
- SoundCloud-приложение на [soundcloud.com/you/apps](https://soundcloud.com/you/apps) — **необязательно** и требует **Artist Pro**. Без ключей работает бесплатный режим с превью Deezer.
- На Windows для установки: iTunes / Apple Devices (Apple Mobile Device Support) + [Sideloadly](https://sideloadly.io/).

## Быстрый старт (Mac)

```bash
open Volna.xcodeproj
```

1. Выберите target **Volna** → **Signing & Capabilities**.
2. **Team**: добавьте свой Apple ID (Add Account) и выберите Personal Team.
3. Bundle Identifier уже задан как `ru.alex.volna` в `Config/App.xcconfig` — при конфликте поменяйте на уникальный, например `ru.<ваше_имя>.volna`.
4. Подключите iPhone, включите на нём **Developer Mode** (Настройки → Конфиденциальность и безопасность → Режим разработчика).
5. Выберите устройство и нажмите **Run**.
6. На iPhone: Настройки → Основные → VPN и управление устройством → доверьте сертификату разработчика.

Подробная инструкция и сборка IPA без Mac: [docs/BUILD-AND-SIDELOAD.md](docs/BUILD-AND-SIDELOAD.md).

## Ключи SoundCloud

1. Зарегистрируйте приложение на [soundcloud.com/you/apps](https://soundcloud.com/you/apps).
2. Скопируйте `Config/Secrets.example.xcconfig` → `Config/Secrets.xcconfig` и заполните:
   ```
   SOUNDCLOUD_CLIENT_ID = ...
   SOUNDCLOUD_CLIENT_SECRET = ...
   ```
3. Либо оставьте файл пустым и введите ключи в самом приложении — они сохранятся в Keychain.

`Config/Secrets.xcconfig` в `.gitignore`. Учтите: Client Secret всё равно попадает в Info.plist собранного приложения, поэтому такая схема допустима только для личной sideload-сборки.

## Проверка API

```powershell
powershell -ExecutionPolicy Bypass -File tools/check-soundcloud-api.ps1
```

Результат пишется в `docs/soundcloud-api-report.json`. Скрипт проверяет OpenAPI, анонимный поиск, oEmbed и OAuth client credentials.

## Структура

```
Volna/
├── Config/                 App.xcconfig, Info.plist, Secrets*.xcconfig
├── Volna/
│   ├── App/                VolnaApp, AppEnvironment, RootView
│   ├── Core/
│   │   ├── API/            SoundCloudAPIClient, Auth, Keychain, RateLimiter
│   │   ├── Models/         доменные модели и DTO
│   │   ├── Recommendations/ движок рекомендаций, FeedViewModel, кэш
│   │   ├── Library/        Core Data, лайки, история, кэш обложек
│   │   ├── Player/         PlaybackController, NowPlaying
│   │   └── Utilities/      настройки, форматтеры
│   ├── DesignSystem/       тема, компоненты, обложки
│   ├── Features/           Onboarding, Feed, Search, Library, Player, Settings, WebFallback
│   └── Resources/          Assets.xcassets, PrivacyInfo.xcprivacy
├── Tests/                  фикстуры (юнит-тестов пока нет)
├── docs/                   отчёт по API
└── tools/                  генератор .xcodeproj, проверка API, иконки
```

## Перегенерация Xcode-проекта

Если добавили/удалили Swift-файлы:

```powershell
powershell -ExecutionPolicy Bypass -File tools/generate-xcodeproj.ps1
```

Скрипт создаёт `Volna.xcodeproj` и shared scheme, записывая `project.pbxproj` без BOM (иначе Xcode не откроет проект).

## Ограничения

- Обход DRM и неофициальных API не используется; офлайн-кэш — только там, где разрешает лицензия.
- Региональные блокировки (например, часть треков sta2tika в РФ) обрабатываются скрытием/заменой трека.
- Бесплатный сертификат Apple: приложение живёт 7 дней, максимум 3 sideload-приложения; переподпись через Sideloadly/AltStore.
- Юнит-тесты и полноценная сборка на Windows невозможны: нет iOS SDK.

## Дисклеймер

Личный некоммерческий проект. Музыка и обложки принадлежат их правообладателям, SoundCloud API используется по правилам сервиса.
