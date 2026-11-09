# Состояние проекта Volna

Обновлено: 2026-11-09.

## Что было сделано 2026-11-08 (DeepSeek Harness)

Сессия `session-5fbf0310-f23b-44e5-9de3-a7596ce50960` в `C:\Users\ALEX\Documents\deepseek-harness\default-workspace`:

- Изучены SoundCloud API (OpenAPI, guide, rate limits, terms), oEmbed и self-serve ключи.
- Установлен Swift-тулчейн для Windows (`winget install Swift.Toolchain`, Swift 6.4.2).
- Создан проект **Volna**: 49 записей файлов и 30 правок.
- Реализованы: сетевой слой (`SoundCloudAPIClient`, OAuth, Keychain, rate limiter), модели и DTO,
  движок рекомендаций (2–3 уровня related), Core Data библиотека, `AVPlayer` + lock screen,
  онбординг, лента, поиск, библиотека, плеер, настройки, Web-embed fallback, иконки приложения.
- Добавлены `tools/check-soundcloud-api.ps1`, `tools/generate-app-icon.ps1`, `tools/generate-xcodeproj.ps1`.
- Сессия оборвалась на шаге 82 с ошибкой **402 Insufficient Balance** (DeepSeek).

## Что сделано 2026-11-09 (OpenCode)

- Проект скопирован в `C:\Users\ALEX\Documents\Проект по умолчанию\Volna`.
- В DeepSeek Harness зарегистрировано workspace **Volna** (назначено по умолчанию).
- Сгенерирован `Volna.xcodeproj` + shared scheme `Volna`; `project.pbxproj` и схема без BOM.
- Исправлены ошибки генератора проекта: `productRefGroup` больше не превращается в
  `System.Collections.Hashtable.products`; добавлена защита от таких утечек.
- Синтаксис всех Swift-файлов проверяется `swiftc -parse` — ошибок нет.
- Исправлено зависание ленты: флаги `isLoading` / `isLoadingMore` теперь снимаются всегда.
- Добавлен **бесплатный режим**: официальный API Deezer без ключей, 30-секундные превью.
  SoundCloud остаётся основным источником и включается автоматически при наличии ключей.
- Поиск артистов стал строже: случайный первый результат больше не подставляется как сид.
- Добавлены `README.md`, `docs/BUILD-AND-SIDELOAD.md`, `docs/SOUNDCLOUD_API_CHECK.md`, этот файл.
- Добавлен CI `.github/workflows/build-ipa.yml` для сборки unsigned IPA на macOS-раннере.

## Режимы работы

| Режим | Условие | Что доступно |
|---|---|---|
| **Бесплатный (по умолчанию)** | Нет ключей SoundCloud | Лента и поиск через Deezer, воспроизведение 30-сек превью |
| **SoundCloud** | Заданы Client ID + Secret | Полные треки, related-граф, все возможности |
| **Web-embed** | Всегда | Официальный виджет SoundCloud по прямой ссылке |

## Что осталось

1. **Сборка `.ipa`** — через GitHub Actions (workflow готов) или macOS/Xcode.
2. **Установка на iPhone** — нужны Apple Mobile Device Support и Sideloadly; телефон уже подключён.
3. **Ключи SoundCloud** (опционально) — нужна подписка Artist Pro.
4. **Тесты** — unit-тесты для `RecommendationEngine`, `RateLimiter`, мапперов DTO и `PreviewCatalog`.
5. **Проверка на устройстве** — поведение превью, доступность Deezer в РФ, автоподстановка треков.
