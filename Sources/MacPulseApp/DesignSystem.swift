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

    static let cyberButtonGradient = LinearGradient(
        colors: [cyan.opacity(0.95), cobalt],
        startPoint: .leading,
        endPoint: .trailing
    )

    static func primaryAccent(quantumMode: Bool) -> Color {
        quantumMode ? violet : cyan
    }
}

// Keep PulseTheme alias pointing to HudTheme so all references stay clean
typealias PulseTheme = HudTheme

// MARK: - 45-Degree Chamfered Sci-Fi Panel Shape (InsettableShape for crisp strokeBorder)
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
        let c = min(cut, min(rect.width, rect.height) * 0.35)
        let r = min(cornerRadius, c * 0.5)
        var p = Path()
        // Top-left (rounded)
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        // Top edge to top-right chamfer
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        // Right edge to bottom-right (rounded)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        // Bottom edge to bottom-left chamfer
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        // Left edge back to top-left
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Corner Targeting Reticle Brackets (⌜ ⌝ ⌞ ⌟)
struct HudCornerBrackets: View {
    let color: Color
    var length: CGFloat = 7
    var lineWidth: CGFloat = 1.25

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // Top-left bracket
                p.move(to: CGPoint(x: 1, y: length))
                p.addLine(to: CGPoint(x: 1, y: 1))
                p.addLine(to: CGPoint(x: length, y: 1))
                // Bottom-right bracket
                p.move(to: CGPoint(x: w - length, y: h - 1))
                p.addLine(to: CGPoint(x: w - 1, y: h - 1))
                p.addLine(to: CGPoint(x: w - 1, y: h - length))
            }
            .stroke(color.opacity(0.72), style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Sci-Fi Blueprint Grid Background Canvas
struct SciFiBackgroundCanvas: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [HudTheme.bgDeep, HudTheme.bgMid, HudTheme.bgDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Ambient holographic light leaks
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

            // Precision tactical micro-grid
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
                ctx.stroke(path, with: .color(accent.opacity(0.038)), lineWidth: 0.6)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Holographic HUD Card Modifier
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
                ZStack {
                    shape.fill(HudTheme.cardBg.opacity(0.92))
                    shape.fill(
                        LinearGradient(
                            colors: [accent.opacity(0.11), accent.opacity(0.015), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.50), accent.opacity(0.14), accent.opacity(0.32)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.95
                )
            )
            .overlay {
                if showBrackets {
                    HudCornerBrackets(color: accent, length: 8, lineWidth: 1.3)
                }
            }
            .shadow(color: Color.black.opacity(0.32), radius: 6, y: 2)
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

    // Backwards-compatible helper mapped to Sci-Fi HUD card
    func telemetryCard(accent: Color? = nil, cornerRadius: CGFloat = 10, padding: CGFloat = 11) -> some View {
        hudCard(accent: accent ?? HudTheme.cyan.opacity(0.65), chamfer: min(10, cornerRadius), padding: padding, showBrackets: accent != nil)
    }
}

// MARK: - Explicit Sci-Fi Action Buttons (Zero macOS Light-Mode Button Artifacts)
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
                ChamferedRect(cut: compact ? 5 : 6, cornerRadius: 3)
                    .fill(
                        filled
                            ? color.opacity(hovering ? 0.34 : 0.22)
                            : HudTheme.insetBg.opacity(hovering ? 0.95 : 0.78)
                    )
            )
            .overlay(
                ChamferedRect(cut: compact ? 5 : 6, cornerRadius: 3)
                    .strokeBorder(color.opacity(filled ? (hovering ? 0.95 : 0.72) : (hovering ? 0.65 : 0.35)), lineWidth: 0.95)
            )
            .foregroundStyle(filled ? HudTheme.textPrimary : color)
            .shadow(color: filled ? color.opacity(hovering ? 0.35 : 0.16) : .clear, radius: 5)
            .opacity(disabled ? 0.45 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

// MARK: - Sci-Fi Styled Toggle Row
struct HudToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var accent: Color = HudTheme.cyan

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isOn.toggle()
            }
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
                // Custom neon hardware switch
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
                        .shadow(color: isOn ? accent.opacity(0.8) : .clear, radius: 3)
                        .padding(.horizontal, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
