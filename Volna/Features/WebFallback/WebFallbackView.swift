import SwiftUI
import UIKit
import WebKit

struct WebFallbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var currentURL: URL?
    @State private var errorMessage: String?
    @State private var recentURLs: [String] = []

    private let recentsKey = "volna.webPlayer.recents"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro

                HStack(spacing: 8) {
                    TextField("https://soundcloud.com/artist/track", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(VolnaTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(VolnaTheme.stroke, lineWidth: 1)
                        )
                        .onSubmit(openURL)

                    Button("Открыть", action: openURL)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(VolnaTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 8) {
                    Button {
                        if let string = UIPasteboard.general.string {
                            urlText = string
                        }
                    } label: {
                        Label("Вставить", systemImage: "doc.on.clipboard")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(VolnaTheme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Только официальный SoundCloud Widget")
                        .font(.system(size: 9))
                        .foregroundStyle(VolnaTheme.textSecondary)
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                if let currentURL {
                    VStack(alignment: .leading, spacing: 8) {
                        SoundCloudWidget(url: currentURL)
                            .frame(height: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(VolnaTheme.stroke, lineWidth: 1)
                            )

                        Text("Виджет проигрывает трек/плейлист средствами SoundCloud. Фоновое управление, очередь и lock screen в этом режиме недоступны.")
                            .font(.system(size: 9))
                            .foregroundStyle(VolnaTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    EmptyStateView(
                        symbol: "safari",
                        title: "Вставь ссылку SoundCloud",
                        message: "Например, ссылку на трек, плейлист или профиль артиста. Это резервный режим, если API-ключи недоступны."
                    )
                }

                if !recentURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Недавние ссылки")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(VolnaTheme.textSecondary)
                            Spacer()
                            Button("Очистить") {
                                recentURLs = []
                                UserDefaults.standard.removeObject(forKey: recentsKey)
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(VolnaTheme.accentSoft)
                        }

                        ForEach(recentURLs, id: \.self) { string in
                            Button {
                                urlText = string
                                openURL()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(VolnaTheme.accentSoft)
                                    Text(string)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(VolnaTheme.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(VolnaTheme.surfaceElevated.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle("Web-плеер")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Закрыть") { dismiss() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VolnaTheme.accentSoft)
            }
        }
        .onAppear {
            recentURLs = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("План Б: официальный виджет")
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(VolnaTheme.textPrimary)
            Text("Прямой API SoundCloud требует Client ID и Client Secret (Artist Pro). Если ключей нет, вставь публичную ссылку — плеер загрузится в официальном iframe SoundCloud.")
                .font(.system(size: 11))
                .foregroundStyle(VolnaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private func openURL() {
        let value = urlText.trimmed
        guard !value.isEmpty else {
            errorMessage = "Вставь ссылку SoundCloud."
            return
        }

        let normalized = value.lowercased().hasPrefix("http") ? value : "https://\(value)"
        guard let url = URL(string: normalized),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "soundcloud.com" || host == "m.soundcloud.com" || host.hasSuffix(".soundcloud.com") else {
            errorMessage = "Нужна публичная HTTPS-ссылка на soundcloud.com."
            return
        }

        let pathParts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard pathParts.count >= 2 else {
            errorMessage = "Ссылка должна вести на трек, плейлист или профиль артиста."
            return
        }

        errorMessage = nil
        currentURL = url
        saveRecent(url.absoluteString)
    }

    private func saveRecent(_ value: String) {
        var recents = recentURLs.filter { $0 != value }
        recents.insert(value, at: 0)
        recentURLs = Array(recents.prefix(6))
        UserDefaults.standard.set(recentURLs, forKey: recentsKey)
    }
}

struct SoundCloudWidget: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(url: url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.load(url: url, in: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        func load(url: URL, in webView: WKWebView) {
            loadedURL = url
            var components = URLComponents(
                url: AppConfiguration.widgetBaseURL,
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "url", value: url.absoluteString),
                URLQueryItem(name: "color", value: "#FF3B4F"),
                URLQueryItem(name: "auto_play", value: "false"),
                URLQueryItem(name: "hide_related", value: "false"),
                URLQueryItem(name: "show_comments", value: "false"),
                URLQueryItem(name: "show_user", value: "true"),
                URLQueryItem(name: "show_reposts", value: "false"),
                URLQueryItem(name: "show_teaser", value: "true"),
                URLQueryItem(name: "visual", value: "true")
            ]
            guard let widgetURL = components?.url else { return }
            webView.load(URLRequest(url: widgetURL))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.host?.contains("soundcloud.com") == true {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
