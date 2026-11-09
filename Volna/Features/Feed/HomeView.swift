import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @Binding var selectedTab: RootView.Tab

    @State private var mixToShow: MixKind?
    @State private var showWebPlayer = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header

                if env.isPreviewMode {
                    previewCard
                }

                tasteStrip

                if case .failed(let message) = env.connectionStatus {
                    ErrorBanner(message: message) {
                        Task { await env.verifyConnection() }
                    }
                }

                mixes

                feedHeader

                if env.feed.items.isEmpty && env.feed.isLoading {
                    LoadingTrackRows()
                } else if env.feed.items.isEmpty {
                    emptyFeed
                } else {
                    feed
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
        .refreshable {
            await env.refreshFeed()
        }
        .task {
            await env.startFeedIfNeeded()
        }
        .sheet(item: $mixToShow) { mix in
            MixDetailView(kind: mix)
                .environmentObject(env)
                .environmentObject(settings)
                .environmentObject(env.library)
        }
        .sheet(isPresented: $showWebPlayer) {
            NavigationStack {
                WebFallbackView()
            }
            .environmentObject(env)
            .environmentObject(settings)
            .environmentObject(env.library)
        }
        .overlay(alignment: .top) {
            if let notice = env.player.notice {
                ToastBanner(text: notice)
                    .padding(.top, 10)
                    .padding(.horizontal, 18)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: env.player.notice)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(VolnaTheme.accent)
                    Text("VOLNA")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(2.4)
                        .foregroundStyle(VolnaTheme.accentSoft)
                }
                Text("Твоя волна")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(VolnaTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VolnaTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                selectedTab = .settings
            } label: {
                ZStack {
                    Circle()
                        .fill(VolnaTheme.surfaceElevated)
                        .frame(width: 44, height: 44)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VolnaTheme.textPrimary)
                }
                .overlay(Circle().stroke(VolnaTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private var subtitle: String {
        if let artist = settings.profile.normalizedArtists.first {
            return "Подобрано под \(artist) и ещё \(max(0, settings.profile.normalizedArtists.count - 1))"
        }
        return "Подобрано под твои жанры"
    }

    private var tasteStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(settings.profile.normalizedArtists.prefix(6), id: \.self) { artist in
                    GenreChip(title: artist, isSelected: true)
                }
                ForEach(settings.profile.normalizedGenres.prefix(3), id: \.self) { genre in
                    GenreChip(title: genre)
                }
            }
        }
        .frame(height: 34)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(VolnaTheme.accentSoft)
                    .frame(width: 46, height: 46)
                    .background(VolnaTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Бесплатный режим")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text("Ключей SoundCloud нет — лента собрана из официальных 30-секундных превью Deezer.")
                        .font(.system(size: 12))
                        .foregroundStyle(VolnaTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button("Полные треки") {
                    selectedTab = .settings
                }
                .buttonStyle(PrimaryButtonStyle(height: 46))

                Button("Web-плеер") {
                    showWebPlayer = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Text("Добавь Client ID и Client Secret SoundCloud (нужна подписка Artist Pro) — и приложение автоматически переключится на полные треки.")
                .font(.system(size: 10))
                .foregroundStyle(VolnaTheme.textSecondary.opacity(0.9))
        }
        .padding(18)
        .volnaCard()
    }

    private var mixes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Миксы")
                    .font(VolnaTheme.fontTitle)
                    .foregroundStyle(VolnaTheme.textPrimary)
                Spacer()
                if env.feed.source == .cache {
                    Text("КЭШ")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MixKind.allCases) { mix in
                        let items = env.feed.items(for: mix)
                        MixCardView(
                            mix: mix,
                            artworkURL: items.first?.track.artworkURL,
                            trackCount: items.count,
                            action: { mixToShow = mix },
                            playAction: {
                                let tracks = items.map(\.track)
                                if !tracks.isEmpty { env.player.play(tracks: tracks) }
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var feedHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Для тебя")
                    .font(VolnaTheme.fontTitle)
                    .foregroundStyle(VolnaTheme.textPrimary)
                Text("Каждый скролл добавляет новые ветки related-графа")
                    .font(.system(size: 10))
                    .foregroundStyle(VolnaTheme.textSecondary)
            }
            Spacer()
            if env.feed.isLoading {
                ProgressView()
                    .tint(VolnaTheme.accent)
                    .scaleEffect(0.8)
            }
        }
        .padding(.top, 2)
    }

    private var feed: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(env.feed.items.enumerated()), id: \.element.id) { index, item in
                TrackRow(track: item.track, reason: item.reason.text)
                    .onAppear {
                        if index >= env.feed.items.count - 4 {
                            Task { await env.feed.loadMore() }
                        }
                    }

                if index < env.feed.items.count - 1 {
                    Divider()
                        .background(VolnaTheme.stroke)
                        .padding(.leading, 68)
                }
            }

            if env.feed.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(VolnaTheme.accent)
                        .padding(.vertical, 18)
                    Spacer()
                }
            } else if !env.feed.hasMore {
                Text("Волна закончилась. Обнови ленту, чтобы найти новые ветки.")
                    .font(.system(size: 11))
                    .foregroundStyle(VolnaTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        }
    }

    private var emptyFeed: some View {
        VStack(spacing: 14) {
            if let message = env.feed.errorMessage {
                ErrorBanner(message: message) {
                    Task { await env.refreshFeed() }
                }
            }
            EmptyStateView(
                symbol: "waveform.path.ecg",
                title: "Волна пока пустая",
                message: "Проверь ключи и соединение. Если регистрация API недоступна, используй Web-плеер с официальным виджетом.",
                actionTitle: "Обновить",
                action: { Task { await env.refreshFeed() } }
            )
            Button("Открыть Web-плеер") {
                showWebPlayer = true
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 220)
        }
    }
}
