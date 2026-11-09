# Сборка и установка Volna на iPhone

Есть два пути: Mac с Xcode (проще) или Windows + GitHub Actions + Sideloadly (без Mac).

> Приложение работает **без ключей SoundCloud**: лента и поиск идут через официальный Deezer API,
> играются официальные 30-секундные превью. Ключи SoundCloud нужны только для полных треков.

---

## Путь A. Mac + Xcode (рекомендуется)

1. Установите Xcode 15+ из App Store.
2. Откройте `Volna.xcodeproj`.
3. Target **Volna** → вкладка **Signing & Capabilities**:
   - **Automatically manage signing** — включено.
   - **Team** — выберите свой Apple ID (кнопка *Add Account*, если список пуст).
   - **Bundle Identifier** — `ru.alex.volna`; если занят, замените в `Config/App.xcconfig` (`APP_BUNDLE_ID`).
4. На iPhone включите **Developer Mode**: Настройки → Конфиденциальность и безопасность → Режим разработчика → перезагрузка.
5. Подключите iPhone кабелем, доверьте компьютеру на телефоне.
6. В Xcode выберите iPhone в списке устройств и нажмите **Run** (⌘R).
7. При первом запуске: Настройки → Основные → VPN и управление устройством → *Доверять* вашему Apple ID.

### Экспорт .ipa из Xcode

1. **Product → Archive**.
2. Organizer → **Distribute App** → **Custom** → **Copy App** (для unsigned) либо **Development** (для signed под ваше устройство).
3. Для Sideloadly нужен `.ipa`: соберите unsigned (`CODE_SIGNING_ALLOWED=NO`) и упакуйте:

```bash
xcodebuild -project Volna.xcodeproj -scheme Volna -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Volna.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" archive

mkdir -p build/Payload
cp -R build/Volna.xcarchive/Products/Applications/Volna.app build/Payload/
cd build && zip -qry Volna-unsigned.ipa Payload
```

---

## Путь B. Windows без Mac (GitHub Actions → Sideloadly)

### 1. Соберите IPA в облаке

1. Создайте репозиторий на GitHub и загрузите папку `Volna` (файл `Config/Secrets.xcconfig` не коммитится — это правильно; CI создаёт пустой).
2. Вкладка **Actions** → workflow **Build unsigned IPA** → **Run workflow**.
3. Дождитесь зелёной галочки (5–10 минут) и скачайте артефакт `Volna-unsigned-ipa`.
4. Распакуйте — внутри `Volna-unsigned.ipa`.

Workflow уже лежит в `.github/workflows/build-ipa.yml` и собирает неподписанный IPA на macOS-раннере.

> Если репозиторий приватный, Actions всё равно бесплатны для публичных репозиториев; для приватных учитывается квота минут.

### 2. Установите на iPhone через Sideloadly

1. Установите на Windows **iTunes** (из Microsoft Store) или **Apple Devices** — нужен Apple Mobile Device Support.
2. Скачайте [Sideloadly](https://sideloadly.io/) и запустите.
3. Подключите iPhone кабелем, разблокируйте и нажмите **Trust**.
4. Перетащите `Volna-unsigned.ipa` в окно Sideloadly.
5. Введите **Apple ID** и пароль (можно создать отдельный Apple ID; 2FA поддерживается).
6. Нажмите **Start**. При первом запуске на iPhone: Настройки → Основные → VPN и управление устройством → доверьте профилю.

### Ограничения бесплатного Apple ID

- Приложение работает **7 дней**, затем нужно переподписать (повторный Start в Sideloadly или AltStore).
- Одновременно можно держать **не более 3** sideload-приложений.
- Некоторые entitlements (push, iCloud, BackgroundTasks сверх audio) недоступны без платного аккаунта.

---

## Ключи SoundCloud (необязательно)

1. [soundcloud.com/you/apps](https://soundcloud.com/you/apps) → **Register a new app** (нужен Artist Pro).
2. Заполните `Config/Secrets.xcconfig` локально **или** введите ключи в приложении (Настройки → SoundCloud) — они сохранятся в Keychain.
3. В облачной сборке ключи не нужны: приложение запустится в бесплатном режиме с превью Deezer, а ключи можно добавить позже в настройках.

Без ключей приложение полностью работоспособно: рекомендации, поиск, плеер, библиотека — но каждый трек звучит 30 секунд (официальное превью Deezer), плеер показывает пометку «только фрагмент».

Проверка доступности API на Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tools/check-soundcloud-api.ps1
```

---

## Если что-то не работает

| Симптом | Решение |
|---|---|
| Xcode не открывает проект | Перегенерируйте: `tools/generate-xcodeproj.ps1` (pbxproj пишется без BOM) |
| «Untrusted Developer» | Настройки → Основные → VPN и управление устройством → Доверять |
| «Unable to install» в Sideloadly | Проверьте Apple Mobile Device Support, разблокируйте iPhone, обновите Sideloadly |
| Приложение закрылось через 7 дней | Переподпишите IPA в Sideloadly |
| Поиск ничего не находит | В бесплатном режиме проверьте сеть до `api.deezer.com`; с ключами SoundCloud — Client ID/Secret и активную подписку Artist Pro |
| Трек не играет | Региональная блокировка или нет preview/streaming URL — приложение подставляет другой трек |
| Играет только 30 секунд | Это бесплатный режим (превью Deezer). Полные треки — только с ключами SoundCloud и Artist Pro |
