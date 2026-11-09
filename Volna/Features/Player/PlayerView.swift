import AVKit
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var isSeeking = false
    @State private var sliderValue: Double = 0
    @State private var appeared = false

    private var track: Track? { env.player.currentTrack }

    var body: some View {
        ZStack {
            if let track {
                ArtworkView(url: track.artworkURL, cornerRadius: 0, showsPlaceholderIcon: false)
                    .scaledToFill()
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .blur(radius: 70)
                    .scaleEffect(1.35)
                    .opacity(0.52)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.15), .black.opacity(0.45), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                AppBackground()
            }

            if let track {
                content(track)
            } else {
                EmptyStateView(
                    symbol: "waveform",
                    title: "Ничего не играет",
                    message: "Выбери трек в волне или библиотеке.",
                    actionTitle: "Закрыть",
                    action: { dismiss() }
                )
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueView()
                .environmentObject(env)
                .environmentObject(library)
        }
        .onAppear {
            sliderValue = env.player.currentTime
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .onChange(of: env.player.currentTime) { value in
            if !isSeeking { sliderValue = value }
        }
        .onChange(of: env.player.currentTrack?.id) { _ in
            isSeeking = false
            sliderValue = 0
        }
    }

    private func content(_ track: Track) -> some View {
        VStack(spacing: 0) {
            topBar(track)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Spacer(minLength: 10)

            ArtworkView(url: track.artworkURL, cornerRadius: 28)
                .frame(maxWidth: 380)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.55), radius: 32, y: 18)
                .padding(.horizontal, 34)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 18)

            trackInfo(track)
                .padding(.horizontal, 28)

            progress
                .padding(.horizontal, 28)
                .padding(.top, 18)

            controls
                .padding(.horizontal, 24)
                .padding(.top, 12)

            bottomBar
                .padding(.horizontal, 30)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            if let notice = env.player.notice {
                ToastBanner(text: notice)
                    .padding(.top, 62)
            }
        }
    }

    private func topBar(_ track: Track) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("СЕЙЧАС ИГРАЕТ")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.5))
                Text("SoundCloud")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
            }

            Spacer()

            Menu {
                Button {
                    let liked = library.toggleLike(track)
                    env.feed.updateSignals(library.signals())
                    _ = liked
                } label: {
                    Label(
                        library.isLiked(track) ? "Убрать из избранного" : "В избранное",
                        systemImage: library.isLiked(track) ? "heart.slash" : "heart"
                    )
                }

                if !library.playlists.isEmpty {
                    Menu {
                        ForEach(library.playlists) { playlist in
                            Button(playlist.title) {
                                library.add(track, to: playlist.id)
                            }
                        }
                    } label: {
                        Label("В плейлист", systemImage: "music.note.list")
                    }
                }

                Button {
                    env.player.enqueueNext(track)
                } label: {
                    Label("Следующим треком", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                if let url = track.permalinkURL {
                    ShareLink(item: url) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                    Link(destination: url) {
                        Label("Открыть на SoundCloud", systemImage: "arrow.up.right.square")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
        }
    }

    private func trackInfo(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(track.artist)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer()

                LikeButton(track: track, size: 23)
            }

            HStack(spacing: 7) {
                PlaybackSourceBadge(track: track)
                if let year = track.yearLabel {
                    Text(year)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                if !track.genre.isEmpty {
                    Text(track.genre)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
                if let url = track.permalinkURL {
                    Link(destination: url) {
                        Text("Открыть")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(VolnaTheme.accentSoft)
                    }
                }
                Spacer()
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 5) {
            Slider(
                value: Binding(
                    get: { isSeeking ? sliderValue : env.player.currentTime },
                    set: { sliderValue = $0 }
                ),
                in: 0...max(env.player.duration, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        env.player.seek(to: sliderValue)
                    }
                }
            )
            .tint(VolnaTheme.accent)
            .disabled(env.player.duration <= 0)

            HStack {
                Text((isSeeking ? sliderValue : env.player.currentTime).clockString)
                Spacer()
                Text(env.player.duration.clockString)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.46))
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button {
                env.player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(env.player.isShuffled ? VolnaTheme.accent : .white.opacity(0.5))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)

            Button {
                env.player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)

            Button {
                env.player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(VolnaTheme.accentGradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: VolnaTheme.accent.opacity(0.45), radius: 22, y: 7)
                    if env.player.isBuffering {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.05)
                    } else {
                        Image(systemName: env.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: env.player.isPlaying ? 0 : 2)
                    }
                }
            }
            .buttonStyle(PressableButtonStyle())

            Button {
                env.player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)

            Button {
                env.player.cycleRepeatMode()
            } label: {
                Image(systemName: env.player.repeatMode.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(env.player.repeatMode.isActive ? VolnaTheme.accent : .white.opacity(0.5))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomBar: some View {
        HStack {
            AirPlayButton()
                .frame(width: 34, height: 34)

            Spacer()

            Button {
                showQueue = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                    Text("Очередь")
                    Text("\(env.player.queue.count)")
                        .foregroundStyle(.white.opacity(0.42))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                env.player.toggleLikeCurrent()
            } label: {
                Image(systemName: track.map(library.isLiked) == true ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(track.map(library.isLiked) == true ? VolnaTheme.accent : .white.opacity(0.7))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white.withAlphaComponent(0.7)
        view.activeTintColor = UIColor(VolnaTheme.accent)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
