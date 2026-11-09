import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    let onComplete: () -> Void

    @State private var step = 0
    @State private var artists: [String] = []
    @State private var genres: [String] = []
    @State private var artistInput = ""
    @State private var genreInput = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var didLoadTaste = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                TabView(selection: $step) {
                    welcomePage.tag(0)
                    tastePage.tag(1)
                    connectPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard !didLoadTaste else { return }
            didLoadTaste = true
            artists = settings.profile.normalizedArtists
            genres = settings.profile.normalizedGenres
        }
    }

    private var header: some View {
        HStack {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(VolnaTheme.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(VolnaTheme.surfaceElevated)
                        .clipShape(Circle())
                }
            } else {
                Color.clear.frame(width: 42, height: 42)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? VolnaTheme.accent : VolnaTheme.stroke)
                        .frame(width: index == step ? 22 : 6, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
                }
            }

            Spacer()

            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 26)

                ZStack {
                    Circle()
                        .fill(VolnaTheme.accent.opacity(0.16))
                        .frame(width: 170, height: 170)
                        .blur(radius: 18)
                    Circle()
                        .stroke(VolnaTheme.accent.opacity(0.28), lineWidth: 1)
                        .frame(width: 132, height: 132)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(VolnaTheme.accentGradient)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(spacing: 10) {
                    Text("VOLNA")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text("Бесконечная волна музыки,\nсобранная под твой вкус.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(VolnaTheme.textSecondary)
                        .lineSpacing(4)
                }

                VStack(spacing: 14) {
                    FeatureRow(symbol: "point.3.connected.trianglepath.dotted", title: "Артисты и related-граф", subtitle: "2–3 уровня похожих исполнителей")
                    FeatureRow(symbol: "infinity", title: "Лента без конца", subtitle: "Новые треки подгружаются по мере скролла")
                    FeatureRow(symbol: "lock.shield", title: "Без DRM и обходов", subtitle: "Только официальный SoundCloud API и Widget")
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 12)

                Button {
                    withAnimation { step = 1 }
                } label: {
                    Text("Настроить вкус")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)

                Text("Для персональной сборки. Ключи SoundCloud хранятся в Keychain.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(VolnaTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(.bottom, 28)
        }
    }

    private var tastePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Что тебе по вкусу?")
                        .font(VolnaTheme.fontDisplay)
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text("Добавь артистов и жанры. Четыре стартовых имени уже внутри — их можно убрать.")
                        .font(.system(size: 13))
                        .foregroundStyle(VolnaTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                inputCard(
                    title: "Артисты",
                    placeholder: "Например, kishlak",
                    text: $artistInput,
                    actionTitle: "Добавить",
                    action: addArtist
                )

                FlowLayout(spacing: 8) {
                    ForEach(artists, id: \.self) { artist in
                        GenreChip(title: artist, isSelected: true) {
                            artists.removeAll { $0.handleKey == artist.handleKey }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Стартовый набор")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VolnaTheme.textSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(AppConfiguration.starterArtists, id: \.self) { artist in
                            let selected = artists.contains { $0.handleKey == artist.handleKey }
                            Button {
                                if selected {
                                    artists.removeAll { $0.handleKey == artist.handleKey }
                                } else {
                                    artists.append(artist)
                                }
                            } label: {
                                GenreChip(title: artist, isSelected: selected)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                inputCard(
                    title: "Жанры",
                    placeholder: "phonk, drift, rap…",
                    text: $genreInput,
                    actionTitle: "Добавить",
                    action: addGenre
                )

                FlowLayout(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        GenreChip(title: genre) {
                            genres.removeAll { $0 == genre }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Популярные жанры")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VolnaTheme.textSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(AppConfiguration.starterGenres, id: \.self) { genre in
                            Button {
                                if genres.contains(genre) {
                                    genres.removeAll { $0 == genre }
                                } else {
                                    genres.append(genre)
                                }
                            } label: {
                                GenreChip(title: genre, isSelected: genres.contains(genre))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    withAnimation { step = 2 }
                } label: {
                    Text("Дальше")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(artists.isEmpty && genres.isEmpty)
                .opacity(artists.isEmpty && genres.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var connectPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Подключи SoundCloud")
                        .font(VolnaTheme.fontDisplay)
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text("Ключи SoundCloud не обязательны: без них работает бесплатный режим с официальными 30-секундными превью. Прямой API SoundCloud требует подписку Artist Pro, зато даёт полные треки.")
                        .font(.system(size: 13))
                        .foregroundStyle(VolnaTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if env.hasCredentials {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(VolnaTheme.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ключи уже настроены")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(VolnaTheme.textPrimary)
                            Text(env.previewClientID() ?? "из конфигурации сборки")
                                .font(.system(size: 11))
                                .foregroundStyle(VolnaTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .volnaCard(cornerRadius: 16)
                }

                VStack(spacing: 12) {
                    field("Client ID", text: $clientID, secret: false)
                    field("Client Secret", text: $clientSecret, secret: true)
                }

                Link(destination: AppConfiguration.registerAppURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                        Text("soundcloud.com/you/apps — создать приложение")
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VolnaTheme.accentSoft)
                    .padding(12)
                    .background(VolnaTheme.accent.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                Button {
                    Task { await finish(connect: true) }
                } label: {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView().tint(.white)
                        }
                        Text(isBusy ? "Проверяем…" : "Проверить и начать")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isBusy)

                Button {
                    Task { await finish(connect: false) }
                } label: {
                    Text("Продолжить в Web-режиме")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isBusy)

                Button {
                    Task { await finish(connect: false) }
                } label: {
                    Text("Настроить позже")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VolnaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .disabled(isBusy)

                Text("Web-режим использует официальный SoundCloud Widget: можно вставить ссылку на трек или плейлист. Фоновое управление и рекомендации в нём недоступны.")
                    .font(.system(size: 10))
                    .foregroundStyle(VolnaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Продолжая, вы соглашаетесь с условиями SoundCloud API. Это персональное приложение, не публикуйте Client Secret.")
                    .font(.system(size: 9))
                    .foregroundStyle(VolnaTheme.textSecondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>, secret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(VolnaTheme.textSecondary)
            Group {
                if secret {
                    SecureField("Вставьте значение", text: text)
                } else {
                    TextField("Вставьте значение", text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(VolnaTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(VolnaTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(VolnaTheme.stroke, lineWidth: 1)
            )
        }
    }

    private func inputCard(
        title: String,
        placeholder: String,
        text: Binding<String>,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(VolnaTheme.textSecondary)
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14))
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(VolnaTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onSubmit(action)
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(VolnaTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func addArtist() {
        let value = artistInput.trimmed
        guard !value.isEmpty else { return }
        if !artists.contains(where: { $0.handleKey == value.handleKey }) {
            artists.append(value)
        }
        artistInput = ""
    }

    private func addGenre() {
        let value = genreInput.normalizedGenre
        guard !value.isEmpty else { return }
        if !genres.contains(value) {
            genres.append(value)
        }
        genreInput = ""
    }

    private func finish(connect: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil

        if connect {
            let id = clientID.trimmed
            let secret = clientSecret.trimmed
            if !id.isEmpty || !secret.isEmpty {
                do {
                    try await env.saveCredentials(clientID: id, clientSecret: secret)
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isBusy = false
                    return
                }
            }
            // No keys is a valid choice: the app continues in the free preview mode.
        }

        await env.updateTaste(artists: artists, genres: genres)
        await env.finishOnboarding()
        isBusy = false
        onComplete()
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VolnaTheme.accentSoft)
                .frame(width: 38, height: 38)
                .background(VolnaTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(VolnaTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(VolnaTheme.textSecondary)
            }
            Spacer()
        }
    }
}

/// A small wrapping HStack replacement that works on iOS 16.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxLineWidth = max(maxLineWidth, x - spacing)
        }
        return CGSize(width: min(maxWidth, maxLineWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
