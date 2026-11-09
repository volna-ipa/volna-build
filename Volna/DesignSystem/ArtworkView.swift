import SwiftUI
import UIKit

struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 18
    var showsPlaceholderIcon: Bool = true

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    VolnaTheme.surfaceElevated,
                    VolnaTheme.accent.opacity(0.35),
                    VolnaTheme.ink
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if showsPlaceholderIcon {
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let loaded = await ArtworkCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                image = loaded
            }
        }
    }
}

struct ArtworkMosaic: View {
    let urls: [URL]
    var cornerRadius: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let cell = (min(proxy.size.width, proxy.size.height) - spacing) / 2
            let padded = urls.isEmpty ? [nil, nil, nil, nil] : (0..<4).map { index in
                urls.indices.contains(index) ? urls[index] : nil
            }

            LazyVGrid(columns: [
                GridItem(.fixed(cell), spacing: spacing),
                GridItem(.fixed(cell), spacing: spacing)
            ], spacing: spacing) {
                ForEach(Array(padded.enumerated()), id: \.offset) { _, url in
                    ArtworkView(url: url, cornerRadius: 0)
                        .frame(width: cell, height: cell)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.width, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
