import SwiftUI
import UIKit

struct PlaybackSourceBadge: View {
    let track: Track

    var body: some View {
        HStack(spacing: 4) {
            if track.isCreativeCommons {
                Text("CC")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(VolnaTheme.secondary.opacity(0.16))
                    .foregroundStyle(VolnaTheme.secondary)
                    .clipShape(Capsule())
            }
            if track.isPreview {
                Text("FRAGMENT")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(VolnaTheme.warning.opacity(0.18))
                    .foregroundStyle(VolnaTheme.warning)
                    .clipShape(Capsule())
            }
        }
    }
}

struct TrackRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let track: Track
    var reason: String? = nil
    var showsArtwork: Bool = true

    private var isCurrent: Bool {
        env.player.currentTrack?.id == track.id
    }

    var body: some View {
        HStack(spacing: 12) {
            if showsArtwork {
                Button {
                    play()
                } label: {
                    ZStack {
                        ArtworkView(url: track.artworkURL, cornerRadius: 12)
                            .frame(width: 56, height: 56)
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.black.opacity(0.42))
                                .frame(width: 56, height: 56)
                            Image(systemName: env.player.isPlaying ? "waveform" : "pause.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                play()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 15, weight: isCurrent ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(isCurrent ? VolnaTheme.accentSoft : VolnaTheme.textPrimary)
                            .lineLimit(1)
                        PlaybackSourceBadge(track: track)
                    }
                    Text(track.artist)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(VolnaTheme.textSecondary)
                        .lineLimit(1)
                    if let reason, !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(VolnaTheme.accentSoft.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(track.duration.clockString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(VolnaTheme.textSecondary)

            Menu {
                Button {
                    let liked = env.library.toggleLike(track)
                    env.feed.updateSignals(env.library.signals())
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    _ = liked
                } label: {
                    Label(
                        env.library.isLiked(track) ? "Убрать из избранного" : "В избранное",
                        systemImage: env.library.isLiked(track) ? "heart.slash" : "heart"
                    )
                }

                Button {
                    env.player.enqueueNext(track)
                } label: {
                    Label("Следующим треком", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    env.player.addToQueue(track)
                } label: {
                    Label("В конец очереди", systemImage: "text.append")
                }

                if !env.library.playlists.isEmpty {
                    Menu {
                        ForEach(env.library.playlists) { playlist in
                            Button(playlist.title) {
                                env.library.add(track, to: playlist.id)
                            }
                        }
                    } label: {
                        Label("В плейлист", systemImage: "music.note.list")
                    }
                }

                if let url = track.permalinkURL {
                    Link(destination: url) {
                        Label("Открыть на SoundCloud", systemImage: "arrow.up.right.square")
                    }
                    ShareLink(item: url) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VolnaTheme.textSecondary)
                    .frame(width: 30, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func play() {
        if isCurrent {
            env.player.togglePlayPause()
        } else {
            env.player.play(track)
        }
    }
}

struct LikeButton: View {
    @EnvironmentObject private var env: AppEnvironment
    let track: Track
    var size: CGFloat = 22

    var body: some View {
        Button {
            let liked = env.library.toggleLike(track)
            env.feed.updateSignals(env.library.signals())
            UIImpactFeedbackGenerator(style: liked ? .medium : .light).impactOccurred()
        } label: {
            Image(systemName: env.library.isLiked(track) ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(env.library.isLiked(track) ? VolnaTheme.accent : VolnaTheme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MixCardView: View {
    let mix: MixKind
    let artworkURL: URL?
    let trackCount: Int
    let action: () -> Void
    let playAction: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(url: artworkURL, cornerRadius: 22, showsPlaceholderIcon: false)
                .frame(width: 272, height: 168)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.25), .black.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                )
                .overlay(
                    LinearGradient(
                        colors: [VolnaTheme.accent.opacity(0.38), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                )

            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: mix.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VolnaTheme.accentSoft)
                Text(mix.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(trackCount) треков · \(mix.subtitle)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .padding(16)
            .padding(.trailing, 48)

            Button(action: playAction) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(VolnaTheme.accent)
                    .clipShape(Circle())
                    .shadow(color: VolnaTheme.accent.opacity(0.45), radius: 12, y: 4)
            }
            .buttonStyle(PressableButtonStyle())
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 272, height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: action)
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var env: AppEnvironment
    let onTap: () -> Void

    var body: some View {
        if let track = env.player.currentTrack {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    let progress = env.player.duration > 0
                        ? min(1, max(0, env.player.currentTime / env.player.duration))
                        : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(VolnaTheme.stroke)
                        Capsule()
                            .fill(VolnaTheme.accentGradient)
                            .frame(width: max(0, proxy.size.width * progress))
                    }
                }
                .frame(height: 2)

                HStack(spacing: 11) {
                    ArtworkView(url: track.artworkURL, cornerRadius: 10)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(VolnaTheme.textPrimary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(VolnaTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        env.player.togglePlayPause()
                    } label: {
                        Image(systemName: env.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(VolnaTheme.textPrimary)
                            .frame(width: 36, height: 44)
                    }
                    .buttonStyle(.plain)

                    Button {
                        env.player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VolnaTheme.textSecondary)
                            .frame(width: 34, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(.ultraThinMaterial)
            .background(VolnaTheme.tabBar.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(VolnaTheme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(VolnaTheme.warning)
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VolnaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button("Повторить", action: retry)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VolnaTheme.accentSoft)
            }
        }
        .padding(12)
        .background(VolnaTheme.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VolnaTheme.warning.opacity(0.18), lineWidth: 1)
        )
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(VolnaTheme.accentSoft.opacity(0.9))
                .frame(width: 64, height: 64)
                .background(VolnaTheme.accent.opacity(0.09))
                .clipShape(Circle())

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(VolnaTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(VolnaTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 220)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

struct ToastBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(VolnaTheme.accentSoft)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.82))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct LoadingTrackRows: View {
    var count: Int = 5

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VolnaTheme.surfaceElevated)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(VolnaTheme.surfaceElevated)
                            .frame(width: 170, height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(VolnaTheme.surfaceElevated.opacity(0.65))
                            .frame(width: 110, height: 10)
                    }
                    Spacer()
                }
            }
        }
        .redacted(reason: .placeholder)
    }
}
