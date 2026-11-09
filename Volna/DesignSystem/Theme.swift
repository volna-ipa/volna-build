import SwiftUI
import UIKit

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .dark: return "Тёмная"
        case .light: return "Светлая"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum VolnaTheme {
    static let accent = Color(hex: 0xFF3B4F)
    static let accentSoft = Color(hex: 0xFF7A66)
    static let secondary = Color(hex: 0x5ED6C0)
    static let warning = Color(hex: 0xFFC857)

    static let ink = Color(hex: 0x08080A)
    static let surface = dynamic(
        light: UIColor(red: 0.96, green: 0.95, blue: 0.95, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.075, blue: 0.09, alpha: 1)
    )
    static let surfaceElevated = dynamic(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
    )
    static let card = dynamic(
        light: UIColor(red: 0.94, green: 0.93, blue: 0.93, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    )
    static let textPrimary = dynamic(
        light: UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1),
        dark: UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1),
        dark: UIColor(red: 0.64, green: 0.64, blue: 0.68, alpha: 1)
    )
    static let stroke = dynamic(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.09)
    )
    static let tabBar = dynamic(
        light: UIColor(red: 0.98, green: 0.97, blue: 0.97, alpha: 0.96),
        dark: UIColor(red: 0.055, green: 0.055, blue: 0.067, alpha: 0.96)
    )

    static let accentGradient = LinearGradient(
        colors: [accent, Color(hex: 0xB21D3B)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x5C0F1D), Color(hex: 0x1A0A0E), ink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let fontDisplay = Font.system(size: 30, weight: .bold, design: .rounded)
    static let fontTitle = Font.system(size: 20, weight: .bold, design: .rounded)
    static let fontBody = Font.system(size: 15, weight: .regular, design: .default)
    static let fontCaption = Font.system(size: 12, weight: .medium, design: .default)

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VolnaTheme.ink
                .ignoresSafeArea()

            if colorScheme == .light {
                Color(hex: 0xF4F1F0).ignoresSafeArea()
            }

            RadialGradient(
                colors: [
                    VolnaTheme.accent.opacity(colorScheme == .dark ? 0.20 : 0.10),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 520
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.clear, VolnaTheme.ink.opacity(colorScheme == .dark ? 0.7 : 0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VolnaTheme.surfaceElevated.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(VolnaTheme.stroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func volnaCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(VolnaTheme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: VolnaTheme.accent.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 18, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(VolnaTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(VolnaTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(VolnaTheme.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct GenreChip: View {
    let title: String
    var isSelected: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(isSelected ? .white : VolnaTheme.textPrimary)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(isSelected ? VolnaTheme.accent : VolnaTheme.surfaceElevated)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.clear : VolnaTheme.stroke, lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(VolnaTheme.fontTitle)
                    .foregroundStyle(VolnaTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(VolnaTheme.fontCaption)
                        .foregroundStyle(VolnaTheme.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VolnaTheme.accentSoft)
            }
        }
    }
}
