import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if env.player.queue.isEmpty {
                        Text("Очередь пуста")
                            .foregroundStyle(VolnaTheme.textSecondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(Array(env.player.queue.enumerated()), id: \.offset) { index, track in
                            let isCurrent = env.player.currentIndex == index
                            Button {
                                env.player.jump(to: index)
                                dismiss()
                            } label: {
                                HStack(spacing: 11) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(isCurrent ? VolnaTheme.accentSoft : VolnaTheme.textSecondary)
                                        .frame(width: 18)

                                    ArtworkView(url: track.artworkURL, cornerRadius: 8)
                                        .frame(width: 42, height: 42)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.system(size: 13, weight: isCurrent ? .bold : .semibold, design: .rounded))
                                            .foregroundStyle(isCurrent ? VolnaTheme.accentSoft : VolnaTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.system(size: 10))
                                            .foregroundStyle(VolnaTheme.textSecondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if isCurrent {
                                        Image(systemName: env.player.isPlaying ? "waveform" : "pause.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(VolnaTheme.accentSoft)
                                    } else {
                                        Text(track.duration.clockString)
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundStyle(VolnaTheme.textSecondary)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(VolnaTheme.stroke)
                            .contextMenu {
                                Button(role: .destructive) {
                                    env.player.removeFromQueue(at: index)
                                } label: {
                                    Label("Убрать из очереди", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    proxy.scrollTo(env.player.currentIndex, anchor: .center)
                }
            }
            .background(AppBackground())
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VolnaTheme.accentSoft)
                }
            }
        }
        .preferredColorScheme(nil)
    }
}
