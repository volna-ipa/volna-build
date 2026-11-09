import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    @State private var showCredentials = false
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var showTasteEditor = false
    @State private var showWebPlayer = false
    @State private var showRemoveCredentials = false
    @State private var cacheBytes: Int64 = 0
    @State private var didLoadCacheSize = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                connectionCard
                tasteCard
                appearanceCard
                storageCard
                webCard
                legalCard
                versionFooter
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .task {
            guard !didLoadCacheSize else { return }
            didLoadCacheSize = true
            let artwork = await ArtworkCache.shared.diskSize()
            let feed = await FeedCache.shared.size()
            cacheBytes = artwork + feed
        }
        .sheet(isPresented: $showTasteEditor) {
            TasteEditorView()
                .environmentObject(env)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showWebPlayer) {
            NavigationStack {
                WebFallbackView()
            }
            .environmentObject(env)
            .environmentObject(settings)
        }
        .confirmationDialog(
            "Удалить сохранённые ключи?",
            isPresented: $showRemoveCredentials,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task {
                    await env.removeSavedCredentials()
                    clientID = ""
                    clientSecret = ""
                    showCredentials = false
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Если ключи заданы в Secrets.xcconfig, приложение продолжит использовать их.")
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(VolnaTheme.accent.opacity(0.14))
                    .frame(width: 58, height: 58)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(VolnaTheme.accentSoft)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Профиль")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(VolnaTheme.textPrimary)
                Text("Настройки звука и подключения")
                    .font(.system(size: 11))
                    .foregroundStyle(VolnaTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SOUNDCLOUD API")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(VolnaTheme.textSecondary)
                Spacer()
                statusBadge
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(env.connectionStatus.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text(connectionSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(VolnaTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            if case .failed(let message) = env.connectionStatus {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(VolnaTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showCredentials {
                VStack(spacing: 9) {
                    credentialField("Client ID", text: $clientID, secret: false)
                    credentialField("Client Secret", text: $clientSecret, secret: true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(VolnaTheme.accentSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 9) {
                    Button {
                        Task { await saveCredentials() }
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                            Text(isSaving ? "Проверяем…" : "Сохранить")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 44))
                    .disabled(isSaving)

                    Button("Отмена") {
                        showCredentials = false
                        errorMessage = nil
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                HStack(spacing: 9) {
                    Button(env.hasCredentials ? "Ввести другие ключи" : "Добавить ключи") {
                        showCredentials = true
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        Task {
                            isTesting = true
                            await env.verifyConnection()
                            isTesting = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if isTesting { ProgressView().scaleEffect(0.7) }
                            Text("Проверить")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VolnaTheme.accentSoft)
                        .frame(height: 44)
                    }
                    .disabled(isTesting)
                }
            }

            if env.hasCredentials {
                HStack {
                    if let preview = env.previewClientID() {
                        Text("Client ID: \(preview)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(VolnaTheme.textSecondary)
                    }
                    Spacer()
                    Button("Удалить ключи") {
                        showRemoveCredentials = true
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VolnaTheme.textSecondary)
                }
            }

            Link(destination: AppConfiguration.registerAppURL) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Регистрация приложения SoundCloud")
                    Spacer()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(VolnaTheme.accentSoft)
            }
        }
        .padding(16)
        .volnaCard()
    }

    private var tasteCard: some View {
        Button {
            showTasteEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ТВОЙ ВКУС")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(VolnaTheme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VolnaTheme.textSecondary)
                }

                FlowLayout(spacing: 6) {
                    ForEach(settings.profile.normalizedArtists.prefix(5), id: \.self) { artist in
                        GenreChip(title: artist, isSelected: true)
                    }
                    ForEach(settings.profile.normalizedGenres.prefix(3), id: \.self) { genre in
                        GenreChip(title: genre)
                    }
                }
            }
            .padding(16)
            .volnaCard()
        }
        .buttonStyle(.plain)
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ОФОРМЛЕНИЕ")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(VolnaTheme.textSecondary)

            Picker("Тема", selection: $settings.themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Тактильный отклик")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text("Легкая вибрация при лайке и переключении")
                        .font(.system(size: 9))
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $settings.hapticsEnabled)
                    .labelsHidden()
                    .tint(VolnaTheme.accent)
            }
        }
        .padding(16)
        .volnaCard()
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ХРАНИЛИЩЕ")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(VolnaTheme.textSecondary)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Кэш обложек и ленты")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
                Spacer()
                Button("Очистить") {
                    Task {
                        await ArtworkCache.shared.clear()
                        await FeedCache.shared.clear()
                        URLCache.shared.removeAllCachedResponses()
                        cacheBytes = 0
                        env.feed.reset()
                    }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(VolnaTheme.accentSoft)
            }

            Divider().background(VolnaTheme.stroke)

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(VolnaTheme.textSecondary)
                Text("Офлайн-режим ограничен метаданными и обложками. SoundCloud API запрещает сохранять аудио для офлайн-прослушивания, даже если трек доступен для скачивания.")
                    .font(.system(size: 9))
                    .foregroundStyle(VolnaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .volnaCard()
    }

    private var webCard: some View {
        Button {
            showWebPlayer = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VolnaTheme.accentSoft)
                    .frame(width: 40, height: 40)
                    .background(VolnaTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Web-плеер SoundCloud")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text("Официальный виджет без API-ключей")
                        .font(.system(size: 10))
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VolnaTheme.textSecondary)
            }
            .padding(16)
            .volnaCard()
        }
        .buttonStyle(.plain)
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("ДОКУМЕНТЫ И ОГРАНИЧЕНИЯ")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(VolnaTheme.textSecondary)

            Link("SoundCloud API Terms", destination: AppConfiguration.apiTermsURL)
            Link("SoundCloud API Guide", destination: AppConfiguration.apiDocsURL)

            Text("Приложение не обходит DRM и не использует неофициальные API. Треки воспроизводятся через официальные stream-эндпоинты или SoundCloud Widget. Офлайн-аудио не сохраняется.")
                .font(.system(size: 9))
                .foregroundStyle(VolnaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Бесплатная подпись Apple ID действует 7 дней. После этого приложение нужно переподписать через Xcode, Sideloadly или AltStore.")
                .font(.system(size: 9))
                .foregroundStyle(VolnaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11, weight: .semibold))
        .tint(VolnaTheme.accentSoft)
        .padding(16)
        .volnaCard()
    }

    private var versionFooter: some View {
        VStack(spacing: 4) {
            Text("VOLNA \(AppConfiguration.appVersion)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(VolnaTheme.textSecondary)
            Text("Личная сборка · не для App Store")
                .font(.system(size: 8))
                .foregroundStyle(VolnaTheme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var statusBadge: some View {
        Text(env.connectionStatus.isConnected ? "ONLINE" : "OFFLINE")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(env.connectionStatus.isConnected ? VolnaTheme.secondary : VolnaTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((env.connectionStatus.isConnected ? VolnaTheme.secondary : VolnaTheme.textSecondary).opacity(0.1))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch env.connectionStatus {
        case .connected: return VolnaTheme.secondary
        case .checking: return VolnaTheme.warning
        case .failed: return VolnaTheme.accent
        case .unknown: return VolnaTheme.textSecondary
        }
    }

    private var connectionSubtitle: String {
        if env.isUsingBundledCredentials() {
            return "Ключи из Secrets.xcconfig"
        }
        if env.hasCredentials {
            return "Ключи хранятся в Keychain этого iPhone"
        }
        return "Бесплатный режим: официальные превью Deezer (30 с)"
    }

    private func credentialField(_ title: String, text: Binding<String>, secret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(VolnaTheme.textSecondary)
            Group {
                if secret {
                    SecureField("Значение", text: text)
                } else {
                    TextField("Значение", text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(VolnaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(VolnaTheme.stroke, lineWidth: 1)
            )
        }
    }

    private func saveCredentials() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            try await env.saveCredentials(clientID: clientID, clientSecret: clientSecret)
            clientID = ""
            clientSecret = ""
            showCredentials = false
            await env.startFeedIfNeeded(force: true)
        } catch let error as SoundCloudAPIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
