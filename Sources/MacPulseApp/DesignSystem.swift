import SwiftUI

enum PulseTheme {
    // Precision scientific color palette
    static let cyan = Color(red: 0.06, green: 0.72, blue: 0.92)
    static let cobalt = Color(red: 0.35, green: 0.45, blue: 0.98)
    static let violet = Color(red: 0.62, green: 0.36, blue: 0.98)
    static let emerald = Color(red: 0.06, green: 0.73, blue: 0.51)
    static let teal = Color(red: 0.08, green: 0.68, blue: 0.66)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.05)
    static let crimson = Color(red: 0.94, green: 0.27, blue: 0.27)

    static let antigravityGradient = LinearGradient(
        colors: [cobalt, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let chatGPTGradient = LinearGradient(
        colors: [emerald, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func canvasBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.055, green: 0.075, blue: 0.115)
            : Color(nsColor: .windowBackgroundColor)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.095, green: 0.125, blue: 0.185)
            : Color(nsColor: .controlBackgroundColor)
    }

    static func cardElevatedFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.125, green: 0.165, blue: 0.24)
            : Color.primary.opacity(0.04)
    }

    static func borderColor(for scheme: ColorScheme, accent: Color? = nil) -> Color {
        if let accent {
            return accent.opacity(scheme == .dark ? 0.35 : 0.28)
        }
        return scheme == .dark ? Color.white.opacity(0.085) : Color.primary.opacity(0.09)
    }
}

struct TelemetryCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let accent: Color?
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(PulseTheme.cardFill(for: scheme))
                    if let accent {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accent.opacity(scheme == .dark ? 0.09 : 0.055),
                                        accent.opacity(0.01)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (accent ?? (scheme == .dark ? Color.white : Color.primary)).opacity(scheme == .dark ? 0.22 : 0.14),
                                PulseTheme.borderColor(for: scheme, accent: accent).opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.9
                    )
            )
    }
}

extension View {
    func telemetryCard(accent: Color? = nil, cornerRadius: CGFloat = 12, padding: CGFloat = 12) -> some View {
        modifier(TelemetryCardModifier(accent: accent, cornerRadius: cornerRadius, padding: padding))
    }
}
