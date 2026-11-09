import SwiftUI

struct LibraryView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case liked = "Избранное"
        case history = "История"
        case playlists = "Плейлисты"
        var id: String { rawValue }
    }

    @EnvironmentObject private var env: AppEnvironment
    @State private var section: Section = .liked
    @State private var showCreatePlaylist = false
    @State private var newPlaylistTitle = ""
    @State private var selectedPlaylist: PlaylistSummary?
    @State private var showClearHistory = false
    @State private var playlistToDelete: PlaylistSummary?

    var body: some View {
        VStack(spacing: 0) {
            header
            stats
            sectionPicker

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    switch section {
                    case .liked:
                        likedContent
                    case .history:
                        historyContent
                    case .playlists:
                        playlistsContent
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .alert("Новый плейлист", isPresented: $showCreatePlaylist) {
            TextField("Название", text: $newPlaylistTitle)
            Button("Отмена", role: .cancel) { newPlaylistTitle = "" }
            Button("Создать") {
                if let playlist = env.library.createPlaylist(title: newPlaylistTitle) {
                    selectedPlaylist = playlist
                }
                newPlaylistTitle = ""
            }
        } message: {
            Text("Собери свой набор треков из волны и библиотеки.")
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .environmentObject(env)
                .environmentObject(env.library)
        }
        .confirmationDialog("Удалить историю?", isPresented: $showClearHistory, titleVisibility: .visible) {
            Button("Очистить историю", role: .destructive) {
                env.library.clearHistory()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Избранное и плейлисты останутся на месте.")
        }
        .confirmationDialog(
            "Удалить плейлист?",
            isPresented: Binding(
                get: { playlistToDelete != nil },
                set: { if !$0 { playlistToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let playlistToDelete {
                    env.library.deletePlaylist(id: playlistToDelete.id)
                }
                playlistToDelete = nil
            }
            Button("Отмена", role: .cancel) { playlistToDelete = nil }
        } message: {
            Text("Треки останутся в SoundCloud и в истории.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Библиотека")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(VolnaTheme.textPrimary)
                Text("Лайки, история и собственные плейлисты")
                    .font(.system(size: 12))
                    .foregroundStyle(VolnaTheme.textSecondary)
            }
            Spacer()
            Button {
                showCreatePlaylist = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(VolnaTheme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            stat(value: env.library.likedTracks.count, label: "лайков", symbol: "heart.fill")
            stat(value: env.library.history.count, label: "прослушано", symbol: "clock.fill")
            stat(value: env.library.playlists.count, label: "плейлистов", symbol: "music.note.list")
        }
        .padding(.horizontal, 18)
    }

    private func stat(value: Int, label: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(VolnaTheme.accentSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(VolnaTheme.textPrimary)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(VolnaTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(VolnaTheme.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(Section.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { section = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(section == item ? .white : VolnaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(section == item ? VolnaTheme.accent : Color.clear)
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
    private var likedContent: some View {
        if env.library.likedTracks.isEmpty {
            EmptyStateView(
                symbol: "heart",
                title: "Здесь пока тихо",
                message: "Лайкай треки в волне или на экране плеера — они появятся здесь и повлияют на рекомендации."
            )
        } else {
            HStack {
                Text("\(env.library.likedTracks.count) треков")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VolnaTheme.textSecondary)
                Spacer()
                Button {
                    env.player.play(tracks: env.library.likedTracks)
                } label: {
                    Label("Играть", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(VolnaTheme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }

            ForEach(env.library.likedTracks) { track in
                TrackRow(track: track)
                Divider()
                    .background(VolnaTheme.stroke)
                    .padding(.leading, 68)
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if env.library.history.isEmpty {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                title: "История пуста",
                message: "Включи первый трек — приложение запомнит его и будет учитывать при подборе."
            )
        } else {
            HStack {
                Text("Недавно")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VolnaTheme.textSecondary)
                Spacer()
                Button("Очистить") { showClearHistory = true }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VolnaTheme.accentSoft)
            }

            ForEach(env.library.history) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    TrackRow(track: entry.track)
                    Text(entry.playedAt.relativeLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(VolnaTheme.textSecondary.opacity(0.8))
                        .padding(.leading, 68)
                        .padding(.bottom, 4)
                }
                Divider()
                    .background(VolnaTheme.stroke)
                    .padding(.leading, 68)
            }

            offlineNote
        }
    }

    @ViewBuilder
    private var playlistsContent: some View {
        if env.library.playlists.isEmpty {
            EmptyStateView(
                symbol: "music.note.list",
                title: "Собери свой плейлист",
                message: "Создай подборку из избранного и рекомендаций. Она хранится локально на iPhone.",
                actionTitle: "Создать плейлист",
                action: { showCreatePlaylist = true }
            )
        } else {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(env.library.playlists) { playlist in
                    Button {
                        selectedPlaylist = playlist
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            ArtworkMosaic(urls: playlist.artworkURLs, cornerRadius: 16)
                                .aspectRatio(1, contentMode: .fit)
                            Text(playlist.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(VolnaTheme.textPrimary)
                                .lineLimit(1)
                            Text("\(playlist.trackCount) треков")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(VolnaTheme.textSecondary)
                        }
                        .padding(10)
                        .background(VolnaTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(VolnaTheme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .contextMenu {
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            Label("Открыть", systemImage: "arrow.up.right")
                        }
                        Button(role: .destructive) {
                            playlistToDelete = playlist
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                showCreatePlaylist = true
            } label: {
                Label("Новый плейлист", systemImage: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VolnaTheme.accentSoft)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(VolnaTheme.accent.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(VolnaTheme.accent.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            offlineNote
        }
    }

    private var offlineNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VolnaTheme.textSecondary)
            Text("Офлайн доступны обложки и метаданные. Аудио не сохраняется: SoundCloud API запрещает офлайн-загрузку пользовательского контента.")
                .font(.system(size: 10))
                .foregroundStyle(VolnaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(VolnaTheme.surfaceElevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 6)
    }
}
