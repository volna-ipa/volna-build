import SwiftUI

struct TasteEditorView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var artists: [String] = []
    @State private var genres: [String] = []
    @State private var artistInput = ""
    @State private var genreInput = ""
    @State private var isSaving = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro

                    editorCard(
                        title: "Артисты",
                        subtitle: "Именно с них начинается related-граф",
                        placeholder: "Имя артиста",
                        text: $artistInput,
                        action: addArtist
                    )

                    FlowLayout(spacing: 8) {
                        ForEach(artists, id: \.self) { artist in
                            GenreChip(title: artist, isSelected: true) {
                                artists.removeAll { $0.handleKey == artist.handleKey }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Стартовый набор")
                            .font(.system(size: 10, weight: .bold))
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

                    editorCard(
                        title: "Жанры",
                        subtitle: "Для микса «Новинки в твоих жанрах»",
                        placeholder: "phonk, rap, drift…",
                        text: $genreInput,
                        action: addGenre
                    )

                    FlowLayout(spacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            GenreChip(title: genre) {
                                genres.removeAll { $0 == genre }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Популярные")
                            .font(.system(size: 10, weight: .bold))
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
                        artists = AppConfiguration.starterArtists
                        genres = AppConfiguration.starterGenres
                    } label: {
                        Label("Вернуть стартовый набор", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VolnaTheme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await save() }
                    } label: {
                        HStack(spacing: 7) {
                            if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                            Text(isSaving ? "Сохраняем…" : "Сохранить и обновить волну")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(artists.isEmpty && genres.isEmpty || isSaving)
                    .opacity(artists.isEmpty && genres.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle("Твой вкус")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            artists = settings.profile.normalizedArtists
            genres = settings.profile.normalizedGenres
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Настрой свою волну")
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(VolnaTheme.textPrimary)
            Text("Добавляй артистов и жанры. Чем точнее вкус, тем меньше случайных треков в ленте.")
                .font(.system(size: 12))
                .foregroundStyle(VolnaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private func editorCard(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(VolnaTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(VolnaTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .onSubmit(action)
                Button {
                    action()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(VolnaTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .volnaCard(cornerRadius: 17)
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

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        await env.updateTaste(artists: artists, genres: genres)
        isSaving = false
        dismiss()
    }
}
