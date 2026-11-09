import SwiftUI

struct MixDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let kind: MixKind

    private var items: [RecommendedTrack] {
        env.feed.items(for: kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    explanation

                    if items.isEmpty {
                        EmptyStateView(
                            symbol: kind.symbol,
                            title: "Микс собирается",
                            message: "Прокрути главную ленту или обнови её — в этот микс попадут треки из related-графа.",
                            actionTitle: "Обновить",
                            action: { Task { await env.refreshFeed() } }
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                TrackRow(track: item.track, reason: item.reason.text)
                                if index < items.count - 1 {
                                    Divider()
                                        .background(VolnaTheme.stroke)
                                        .padding(.leading, 68)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(kind.shortTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(VolnaTheme.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(VolnaTheme.surfaceElevated)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .preferredColorScheme(nil)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(url: items.first?.track.artworkURL, cornerRadius: 24, showsPlaceholderIcon: false)
                .frame(height: 220)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.3), .black.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )

            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(VolnaTheme.accentSoft)
                Text(kind.title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(items.count) треков · \(kind.subtitle)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))

                Button {
                    let tracks = items.map(\.track)
                    if !tracks.isEmpty {
                        env.player.play(tracks: tracks)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text("Играть всё")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(VolnaTheme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0.5 : 1)
                .padding(.top, 4)
            }
            .padding(18)
        }
        .padding(.top, 8)
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(VolnaTheme.accentSoft)
                .font(.system(size: 13))
            Text(explanationText)
                .font(.system(size: 11))
                .foregroundStyle(VolnaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(VolnaTheme.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var explanationText: String {
        switch kind {
        case .forYou:
            return "Треки твоих артистов и исполнителей, найденных через related-граф SoundCloud. Creative Commons получают приоритет."
        case .newInGenres:
            return "Свежие треки в жанрах из твоего профиля. Если у трека несколько тегов, он может попасть в оба микса."
        }
    }
}
