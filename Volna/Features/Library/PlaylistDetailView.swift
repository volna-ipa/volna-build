import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let playlist: PlaylistSummary

    @State private var tracks: [Track] = []
    @State private var currentTitle = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if tracks.isEmpty {
                        EmptyStateView(
                            symbol: "music.note",
                            title: "Плейлист пуст",
                            message: "Открой трек в плеере и выбери «В плейлист», чтобы добавить его сюда."
                        )
                    } else {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track)
                                .contextMenu {
                                    Button {
                                        env.player.enqueueNext(track)
                                    } label: {
                                        Label("Следующим треком", systemImage: "text.line.first.and.arrowtriangle.forward")
                                    }
                                    Button(role: .destructive) {
                                        library.remove(trackID: track.id, from: playlist.id)
                                        reload()
                                    } label: {
                                        Label("Убрать из плейлиста", systemImage: "minus.circle")
                                    }
                                }
                            if index < tracks.count - 1 {
                                Divider()
                                    .background(VolnaTheme.stroke)
                                    .padding(.leading, 68)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(currentTitle.isEmpty ? playlist.title : currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(VolnaTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            renameText = currentTitle
                            showRename = true
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDelete = true
                        } label: {
                            Label("Удалить плейлист", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(VolnaTheme.textPrimary)
                    }
                }
            }
        }
        .onAppear {
            currentTitle = playlist.title
            reload()
        }
        .onChange(of: library.playlists) { _ in
            reload()
            if let updated = library.playlists.first(where: { $0.id == playlist.id }) {
                currentTitle = updated.title
            }
        }
        .alert("Переименовать", isPresented: $showRename) {
            TextField("Название", text: $renameText)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                library.renamePlaylist(id: playlist.id, title: renameText)
            }
        }
        .confirmationDialog("Удалить плейлист?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                library.deletePlaylist(id: playlist.id)
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArtworkMosaic(urls: playlist.artworkURLs, cornerRadius: 24)
                .frame(width: 180, height: 180)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 5) {
                Text(currentTitle.isEmpty ? playlist.title : currentTitle)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(VolnaTheme.textPrimary)
                Text("\(tracks.count) треков · локальный плейлист")
                    .font(.system(size: 11))
                    .foregroundStyle(VolnaTheme.textSecondary)
            }

            HStack(spacing: 10) {
                Button {
                    if !tracks.isEmpty {
                        env.player.play(tracks: tracks)
                        dismiss()
                    }
                } label: {
                    Label("Играть всё", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(height: 46))
                .disabled(tracks.isEmpty)
                .opacity(tracks.isEmpty ? 0.5 : 1)

                Button {
                    if let first = tracks.first {
                        env.player.enqueueNext(first)
                    }
                } label: {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(VolnaTheme.textPrimary)
                        .frame(width: 50, height: 46)
                        .background(VolnaTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)
            }
        }
    }

    private func reload() {
        tracks = library.tracks(in: playlist.id)
    }
}
