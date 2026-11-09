import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    @State private var selectedTab: Tab = .home
    @State private var showPlayer = false
    @State private var showOnboarding = false
    @State private var didEvaluateOnboarding = false

    enum Tab: Hashable {
        case home
        case search
        case library
        case settings
    }

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab)
                    .tag(Tab.home)
                    .tabItem {
                        Label("Волна", systemImage: selectedTab == .home ? "waveform" : "waveform")
                    }

                SearchView(selectedTab: $selectedTab)
                    .tag(Tab.search)
                    .tabItem {
                        Label("Поиск", systemImage: "magnifyingglass")
                    }

                LibraryView()
                    .tag(Tab.library)
                    .tabItem {
                        Label("Библиотека", systemImage: "heart.fill")
                    }

                SettingsView()
                    .tag(Tab.settings)
                    .tabItem {
                        Label("Профиль", systemImage: "person.crop.circle")
                    }
            }
            .tint(VolnaTheme.accent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if env.player.hasTrack && !showOnboarding && !showPlayer {
                    MiniPlayer {
                        showPlayer = true
                    }
                    .padding(.top, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(env)
                .environmentObject(settings)
                .environmentObject(env.library)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
            }
            .environmentObject(env)
            .environmentObject(settings)
            .environmentObject(env.library)
        }
        .onAppear {
            guard !didEvaluateOnboarding else { return }
            didEvaluateOnboarding = true
            if !settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: settings.hasCompletedOnboarding) { completed in
            if completed && showOnboarding {
                showOnboarding = false
            }
        }
        .onChange(of: env.player.currentTrack?.id) { _ in
            if env.player.currentTrack != nil {
                // Keep the mini player visible without forcing the full player open.
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: env.player.currentTrack?.id)
    }
}
