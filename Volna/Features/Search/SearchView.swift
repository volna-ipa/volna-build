import SwiftUI

struct SearchView: View {
    private enum SearchScope: String, CaseIterable, Identifiable {
        case tracks = "Треки"
        case artists = "Артисты"
        var id: String { rawValue }
    }

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @Binding var selectedTab: RootView.Tab

    @State private var query = ""
    @State private var scope: SearchScope = .tracks
    @State private var tracks: [Track] = []
    @State private var artists: [Artist] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var recentSearches: [String] = []
    @State private var searchGeneration = 0
    @FocusState private var searchFocused: Bool

    private let recentsKey = "volna.recentSearches"

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            scopePicker

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if query.trimmed.count < 2 {
                        suggestions
                    } else {
                        results
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task(id: "\(query)|\(scope.rawValue)|\(env.isPreviewMode)") {
            await searchIfNeeded()
        }
        .onAppear {
            recentSearches = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Поиск")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(VolnaTheme.textPrimary)
                Text("Найди артиста и добавь его в свою волну")
                    .font(.system(size: 12))
                    .foregroundStyle(VolnaTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(VolnaTheme.accentSoft)
                .frame(width: 44, height: 44)
                .background(VolnaTheme.accent.opacity(0.1))
                .clipShape(Circle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VolnaTheme.textSecondary)

            TextField("kishlak, phonk, sta2tika…", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VolnaTheme.textPrimary)
                .onSubmit(commitSearch)

            if !query.isEmpty {
                Button {
                    query = ""
                    tracks = []
                    artists = []
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(VolnaTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(searchFocused ? VolnaTheme.accent.opacity(0.55) : VolnaTheme.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var scopePicker: some View {
        HStack(spacing: 6) {
            ForEach(SearchScope.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { scope = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(scope == item ? .white : VolnaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(scope == item ? VolnaTheme.accent : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(VolnaTheme.surfaceElevated.opacity(0.7))
        .clipShape(Capsule())
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var results: some View {
        if isLoading {
            LoadingTrackRows(count: 4)
        } else if let errorMessage {
            ErrorBanner(message: errorMessage) {
                Task { await runSearch(commit: false) }
            }
        } else if scope == .tracks {
            if tracks.isEmpty {
                EmptyStateView(
                    symbol: "music.note.list",
                    title: "Ничего не нашлось",
                    message: "Попробуй другой запрос, жанр или имя артиста латиницей."
                )
            } else {
                HStack {
                    Text("Треки")
                        .font(VolnaTheme.fontTitle)
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Spacer()
                    Text("\(tracks.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
                ForEach(tracks) { track in
                    TrackRow(track: track)
                }
            }
        } else {
            if artists.isEmpty {
                EmptyStateView(
                    symbol: "person.crop.circle.badge.questionmark",
                    title: "Артист не найден",
                    message: "Проверь написание или попробуй найти трек и добавить исполнителя из его карточки."
                )
            } else {
                ForEach(artists) { artist in
                    ArtistSearchRow(artist: artist)
                }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Недавние запросы")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(VolnaTheme.textSecondary)
                        Spacer()
                        Button("Очистить") {
                            recentSearches = []
                            UserDefaults.standard.removeObject(forKey: recentsKey)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VolnaTheme.accentSoft)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(recentSearches, id: \.self) { item in
                            Button {
                                query = item
                                commitSearch()
                            } label: {
                                GenreChip(title: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Твои артисты")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VolnaTheme.textSecondary)
                FlowLayout(spacing: 8) {
                    ForEach(AppConfiguration.starterArtists, id: \.self) { artist in
                        Button {
                            query = artist
                            scope = .artists
                        } label: {
                            GenreChip(
                                title: artist,
                                isSelected: settings.profile.normalizedArtists.contains {
                                    $0.handleKey == artist.handleKey
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Жанры")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VolnaTheme.textSecondary)
                FlowLayout(spacing: 8) {
                    ForEach(settings.profile.normalizedGenres, id: \.self) { genre in
                        Button {
                            query = genre
                            scope = .tracks
                        } label: {
                            GenreChip(title: genre)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(VolnaTheme.warning)
                Text("Совет: ищи артиста латиницей и добавляй его в профиль — related-граф сам найдёт соседей по звуку.")
                    .font(.system(size: 11))
                    .foregroundStyle(VolnaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(VolnaTheme.warning.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func searchIfNeeded() async {
        let value = query.trimmed
        guard value.count >= 2 else {
            if !isLoading {
                tracks = []
                artists = []
                errorMessage = nil
            }
            return
        }
        await runSearch(commit: false)
    }

    private func runSearch(commit: Bool) async {
        let value = query.trimmed
        guard value.count >= 2 else { return }

        searchGeneration += 1
        let generation = searchGeneration
        isLoading = true
        errorMessage = nil

        do {
            try await Task.sleep(nanoseconds: 320_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled, generation == searchGeneration else { return }

        do {
            if scope == .tracks {
                let page = try await env.api.searchTracksPage(query: value, limit: 40)
                guard generation == searchGeneration else { return }
                tracks = page.tracks
                artists = []
            } else {
                let page = try await env.api.searchArtistsPage(query: value, limit: 30)
                guard generation == searchGeneration else { return }
                artists = page.artists
                tracks = []
            }
            if commit {
                saveRecent(value)
            }
        } catch let error as SoundCloudAPIError {
            guard generation == searchGeneration else { return }
            if case .cancelled = error { return }
            errorMessage = error.errorDescription
        } catch {
            guard generation == searchGeneration else { return }
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }

        if generation == searchGeneration {
            isLoading = false
        }
    }

    private func commitSearch() {
        let value = query.trimmed
        guard value.count >= 2 else { return }
        saveRecent(value)
        searchFocused = false
        Task { await runSearch(commit: true) }
    }

    private func saveRecent(_ value: String) {
        var recents = recentSearches.filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        recents.insert(value, at: 0)
        recentSearches = Array(recents.prefix(8))
        UserDefaults.standard.set(recentSearches, forKey: recentsKey)
    }
}

private struct ArtistSearchRow: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    let artist: Artist

    private var isAdded: Bool {
        settings.profile.normalizedArtists.contains { $0.handleKey == artist.username.handleKey }
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: artist.avatarURL, cornerRadius: 24)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(artist.username)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(VolnaTheme.textPrimary)
                    .lineLimit(1)
                Text("\(artist.followersCount.compactCount) подписчиков · \(artist.trackCount) треков")
                    .font(.system(size: 11))
                    .foregroundStyle(VolnaTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                if isAdded {
                    settings.removeArtist(artist.username)
                } else {
                    settings.addArtist(artist.username)
                    env.feed.reset()
                    Task { await env.startFeedIfNeeded(force: true) }
                }
            } label: {
                Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isAdded ? VolnaTheme.secondary : .white)
                    .frame(width: 36, height: 36)
                    .background(isAdded ? VolnaTheme.secondary.opacity(0.12) : VolnaTheme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(12)
        .volnaCard(cornerRadius: 16)
    }
}
