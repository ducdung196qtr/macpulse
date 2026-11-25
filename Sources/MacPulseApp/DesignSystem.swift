import SwiftUI

enum HudTheme {
    // Explicit deep-space Sci-Fi HUD palette (100% immune to macOS Light Mode popover bugs)
    static let bgDeep      = Color(red: 0.020, green: 0.039, blue: 0.078) // #050A14
    static let bgMid       = Color(red: 0.031, green: 0.063, blue: 0.125) // #081020
    static let cardBg      = Color(red: 0.047, green: 0.090, blue: 0.165) // #0C172A
    static let cardBgHi    = Color(red: 0.067, green: 0.122, blue: 0.216) // #111F37
    static let insetBg     = Color(red: 0.027, green: 0.055, blue: 0.106) // #070E1B

    // High-contrast crisp typography colors (WCAG AAA on dark HUD)
    static let textPrimary   = Color(red: 0.93, green: 0.97, blue: 1.00)  // #EDF7FF
    static let textSecondary = Color(red: 0.58, green: 0.71, blue: 0.87)  // #94B5DE
    static let textMuted     = Color(red: 0.37, green: 0.49, blue: 0.66)  // #5E7DA8

    // Neon holographic signal colors
    static let cyan    = Color(red: 0.00, green: 0.88, blue: 1.00) // #00E0FF
    static let cobalt  = Color(red: 0.33, green: 0.52, blue: 1.00) // #5485FF
    static let violet  = Color(red: 0.68, green: 0.40, blue: 1.00) // #AD66FF
    static let emerald = Color(red: 0.07, green: 0.92, blue: 0.64) // #12EBA3
    static let teal    = Color(red: 0.06, green: 0.82, blue: 0.80) // #0FD1CC
    static let amber   = Color(red: 1.00, green: 0.72, blue: 0.12) // #FFB81F
    static let crimson = Color(red: 1.00, green: 0.28, blue: 0.38) // #FF4761

    static let antigravityGradient = LinearGradient(
        colors: [cyan, cobalt, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let chatGPTGradient = LinearGradient(
        colors: [emerald, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func primaryAccent(quantumMode: Bool) -> Color {
        quantumMode ? violet : cyan
    }
}

typealias PulseTheme = HudTheme

// MARK: - 45-Degree Chamfered Sci-Fi Panel Shape (InsettableShape)
struct ChamferedRect: InsettableShape {
    var cut: CGFloat = 10
    var cornerRadius: CGFloat = 4
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> ChamferedRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rawRect: CGRect) -> Path {
        let rect = rawRect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 2, rect.height > 2 else { return Path(rect) }
        let c = min(cut, min(rect.width, rect.height) * 0.35)
        let r = min(cornerRadius, c * 0.5)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Lightweight Vector Corner Brackets (Zero GeometryReader overhead via Shape)
struct HudCornerBracketsShape: Shape {
    var length: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let l = min(length, min(rect.width, rect.height) * 0.3)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX + 1, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY + 1))

        p.move(to: CGPoint(x: rect.maxX - l, y: rect.maxY - 1))
        p.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 1))
        p.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - l))
        return p
    }
}

// MARK: - Metal-Cached Sci-Fi Blueprint Background (Rendered Once into GPU Texture)
struct SciFiBackgroundCanvas: View, Equatable {
    let accent: Color

    static func == (lhs: SciFiBackgroundCanvas, rhs: SciFiBackgroundCanvas) -> Bool {
        lhs.accent == rhs.accent
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [HudTheme.bgDeep, HudTheme.bgMid, HudTheme.bgDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [accent.opacity(0.14), .clear],
                center: UnitPoint(x: 0.12, y: 0.04),
                startRadius: 10,
                endRadius: 280
            )
            RadialGradient(
                colors: [HudTheme.violet.opacity(0.10), .clear],
                center: UnitPoint(x: 0.92, y: 0.88),
                startRadius: 10,
                endRadius: 260
            )

            Canvas { ctx, size in
                let step: CGFloat = 24
                var path = Path()
                var x: CGFloat = step
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = step
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                ctx.stroke(path, with: .color(accent.opacity(0.04)), lineWidth: 0.6)
            }
        }
        .drawingGroup(opaque: true)
        .ignoresSafeArea()
    }
}

// MARK: - Zero-Shadow High-Performance Holographic HUD Card
struct HudCardModifier: ViewModifier {
    let accent: Color
    let chamfer: CGFloat
    let padding: CGFloat
    let showBrackets: Bool

    func body(content: Content) -> some View {
        let shape = ChamferedRect(cut: chamfer, cornerRadius: 5)
        content
            .padding(padding)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [
                            HudTheme.cardBgHi.opacity(0.95),
                            HudTheme.cardBg.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.55), accent.opacity(0.14), accent.opacity(0.32)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.95
                )
            )
            .overlay {
                if showBrackets {
                    HudCornerBracketsShape(length: 8)
                        .stroke(accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.3, lineCap: .square))
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func hudCard(
        accent: Color = HudTheme.cyan,
        chamfer: CGFloat = 9,
        padding: CGFloat = 11,
        showBrackets: Bool = false
    ) -> some View {
        modifier(HudCardModifier(accent: accent, chamfer: chamfer, padding: padding, showBrackets: showBrackets))
    }

    func telemetryCard(accent: Color? = nil, cornerRadius: CGFloat = 10, padding: CGFloat = 11) -> some View {
        hudCard(accent: accent ?? HudTheme.cyan.opacity(0.65), chamfer: min(10, cornerRadius), padding: padding, showBrackets: accent != nil)
    }
}

// MARK: - Zero-Shadow Explicit Sci-Fi Button
struct HudButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = HudTheme.cyan
    var filled: Bool = true
    var compact: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = ChamferedRect(cut: compact ? 5 : 6, cornerRadius: 3)
        Button(action: action) {
            HStack(spacing: compact ? 3.5 : 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 9.5 : 10.5, weight: .bold))
                }
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 7.5 : 10)
            .padding(.vertical, compact ? 4 : 5.5)
            .background(
                shape.fill(
                    filled
                        ? color.opacity(hovering ? 0.36 : 0.24)
                        : HudTheme.insetBg.opacity(hovering ? 1.0 : 0.85)
                )
            )
            .overlay(
                shape.strokeBorder(color.opacity(filled ? (hovering ? 1.0 : 0.78) : (hovering ? 0.75 : 0.40)), lineWidth: 0.95)
            )
            .foregroundStyle(filled ? HudTheme.textPrimary : color)
            .opacity(disabled ? 0.45 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

// MARK: - Zero-Shadow Sci-Fi Hardware Toggle Row
struct HudToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var accent: Color = HudTheme.cyan

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(HudTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(HudTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? accent.opacity(0.28) : HudTheme.insetBg)
                        .overlay(
                            Capsule()
                                .strokeBorder(isOn ? accent.opacity(0.85) : HudTheme.textMuted.opacity(0.45), lineWidth: 1)
                        )
                        .frame(width: 34, height: 18)

                    Circle()
                        .fill(isOn ? accent : HudTheme.textMuted)
                        .frame(width: 12, height: 12)
                        .padding(.horizontal, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
