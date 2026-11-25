import SwiftUI
import MacPulseCore

// MARK: - Tactical Sci-Fi Section Header (`// TITLE ───── [TAG]`)
struct SectionEyebrow: View {
    let icon: String
    let title: String
    var color: Color = HudTheme.cyan
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.6), radius: 3)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(HudTheme.textSecondary)

            // Tactical scanning hairline
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.45), color.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.8)

            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(color.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.7))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Arc Reactor Health Gauge (3-Layer Holographic Core)
struct ArcHealthGauge: View {
    let score: Int
    let color: Color
    var size: CGFloat = 44

    private var progress: Double {
        max(0, min(1, Double(score) / 100.0))
    }

    var body: some View {
        ZStack {
            // Outer radar dial ticks (24 ticks)
            ForEach(0..<24, id: \.self) { idx in
                let major = (idx % 6 == 0)
                Rectangle()
                    .fill(major ? color.opacity(0.55) : HudTheme.textMuted.opacity(0.30))
                    .frame(width: major ? 1.2 : 0.8, height: major ? size * 0.095 : size * 0.055)
                    .offset(y: -size * 0.48)
                    .rotationEffect(.degrees(Double(idx) * 15.0))
            }

            // Inner dashed orbital ring
            Circle()
                .stroke(
                    color.opacity(0.24),
                    style: StrokeStyle(lineWidth: 0.9, dash: [2.5, 3])
                )
                .frame(width: size * 0.64, height: size * 0.64)

            // Track ring
            Circle()
                .trim(from: 0.125, to: 0.875)
                .stroke(
                    HudTheme.insetBg,
                    style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)
                )
                .frame(width: size * 0.82, height: size * 0.82)
                .rotationEffect(.degrees(90))

            // Active plasma energy arc
            Circle()
                .trim(from: 0.125, to: 0.125 + 0.75 * progress)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.5), color, Color.white.opacity(0.95)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(300)
                    ),
                    style: StrokeStyle(lineWidth: size * 0.105, lineCap: .round)
                )
                .frame(width: size * 0.82, height: size * 0.82)
                .rotationEffect(.degrees(90))
                .shadow(color: color.opacity(0.75), radius: 4)
                .animation(.easeOut(duration: 0.45), value: progress)

            // Center score readout
            Text("\(score)")
                .font(.system(size: size * 0.32, weight: .black, design: .monospaced))
                .foregroundStyle(HudTheme.textPrimary)
                .shadow(color: color.opacity(0.65), radius: 4)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Neon Oscilloscope Waveform (Sci-Fi Live Sparkline)
struct LiveSparklineView: View {
    let samples: [Double]
    let color: Color
    var maxValue: Double = 100.0
    var height: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts: [Double] = samples.count >= 2 ? samples : [samples.first ?? 0, samples.first ?? 0]
            let count = pts.count
            let stepX = w / CGFloat(max(1, count - 1))

            ZStack {
                // Dark recessed oscilloscope screen
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(HudTheme.insetBg.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(color.opacity(0.16), lineWidth: 0.6)
                    )

                // Micro gridlines
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.33))
                    p.addLine(to: CGPoint(x: w, y: h * 0.33))
                    p.move(to: CGPoint(x: 0, y: h * 0.66))
                    p.addLine(to: CGPoint(x: w, y: h * 0.66))
                    p.move(to: CGPoint(x: w * 0.5, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h))
                }
                .stroke(color.opacity(0.09), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

                // Plasma area fill
                Path { path in
                    for (i, val) in pts.enumerated() {
                        let norm = max(0.04, min(0.96, val / max(1.0, maxValue)))
                        let x = CGFloat(i) * stepX
                        let y = h - CGFloat(norm) * (h - 4) - 2
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: h))
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.38), color.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Outer neon bloom stroke
                waveformPath(pts: pts, stepX: stepX, h: h)
                    .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                    .blur(radius: 1.4)

                // Crisp core beam stroke
                waveformPath(pts: pts, stepX: stepX, h: h)
                    .stroke(
                        LinearGradient(colors: [color, Color.white.opacity(0.9)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )

                // Live target pulse node
                if let last = pts.last {
                    let norm = max(0.04, min(0.96, last / max(1.0, maxValue)))
                    let y = h - CGFloat(norm) * (h - 4) - 2
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .shadow(color: color, radius: 3.5)
                        .position(x: max(2, w - 2.5), y: y)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: height)
    }

    private func waveformPath(pts: [Double], stepX: CGFloat, h: CGFloat) -> Path {
        Path { path in
            for (i, val) in pts.enumerated() {
                let norm = max(0.04, min(0.96, val / max(1.0, maxValue)))
                let x = CGFloat(i) * stepX
                let y = h - CGFloat(norm) * (h - 4) - 2
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }
}

// MARK: - Segmented Memory Allocation Bar (Glowing Plasma Layers)
struct SegmentedMemoryBar: View {
    let memory: MemoryMetrics
    var height: CGFloat = 5.5

    var body: some View {
        let total = max(1.0, Double(memory.totalBytes))
        let appFrac = min(1.0, Double(memory.effectiveAppMemoryBytes) / total)
        let wiredFrac = min(1.0 - appFrac, Double(memory.wiredBytes) / total)
        let compFrac = min(1.0 - appFrac - wiredFrac, Double(memory.compressedBytes) / total)
        let cacheFrac = min(1.0 - appFrac - wiredFrac - compFrac, Double(memory.cachedFilesBytes) / total)

        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(HudTheme.insetBg)
                    .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(HudTheme.cyan.opacity(0.18), lineWidth: 0.5))

                HStack(spacing: 1.5) {
                    if appFrac > 0.005 {
                        Rectangle()
                            .fill(HudTheme.cyan)
                            .frame(width: max(2, w * CGFloat(appFrac)))
                    }
                    if wiredFrac > 0.005 {
                        Rectangle()
                            .fill(HudTheme.cobalt)
                            .frame(width: max(2, w * CGFloat(wiredFrac)))
                    }
                    if compFrac > 0.005 {
                        Rectangle()
                            .fill(HudTheme.amber)
                            .frame(width: max(2, w * CGFloat(compFrac)))
                    }
                    if cacheFrac > 0.005 {
                        Rectangle()
                            .fill(HudTheme.teal.opacity(0.55))
                            .frame(width: max(2, w * CGFloat(cacheFrac)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2.5))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Holographic LED Segmented Progress Bar
struct TickProgressBar: View {
    let ratio: Double // 0...1
    let color: Color
    var height: CGFloat = 7
    var showTicks: Bool = true
    var segments: Int = 20

    var body: some View {
        let clamped = max(0, min(1, ratio))
        let litCount = Int((clamped * Double(segments)).rounded(.up))

        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { idx in
                let isLit = clamped > 0.001 && idx < litCount
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        isLit
                            ? (idx == litCount - 1 ? Color.white.opacity(0.95) : color)
                            : HudTheme.insetBg
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5)
                            .strokeBorder(isLit ? color.opacity(0.5) : color.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: isLit ? color.opacity(0.55) : .clear, radius: 2)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: litCount)
    }
}

// MARK: - Orbital Hologram Quota Ring
struct QuotaRingView: View {
    let remainingPercent: Double
    let color: Color
    var size: CGFloat = 46
    var lineWidth: CGFloat = 4.2

    private var frac: Double {
        max(0, min(1, remainingPercent / 100.0))
    }

    var body: some View {
        ZStack {
            // Outer orbital crosshair circle
            Circle()
                .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                .frame(width: size, height: size)

            // Recessed track
            Circle()
                .stroke(HudTheme.insetBg, lineWidth: lineWidth)
                .frame(width: size * 0.84, height: size * 0.84)

            // Glowing orbital arc
            Circle()
                .trim(from: 0, to: frac)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.65), color, Color.white.opacity(0.9)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size * 0.84, height: size * 0.84)
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.65), radius: 3.5)
                .animation(.easeOut(duration: 0.4), value: frac)

            VStack(spacing: -2) {
                Text("\(Int(remainingPercent.rounded()))")
                    .font(.system(size: size * 0.28, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textPrimary)
                Text("%")
                    .font(.system(size: size * 0.15, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Live Telemetry Beacon Dot
struct LivePulseDot: View {
    let color: Color
    var isLive: Bool = true
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .stroke(color.opacity(0.65), lineWidth: 1.2)
                    .frame(width: 11, height: 11)
                    .scaleEffect(pulsing ? 1.55 : 0.6)
                    .opacity(pulsing ? 0.0 : 0.85)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulsing)
            }
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.9), radius: 3)
        }
        .frame(width: 12, height: 12)
        .onAppear {
            if isLive { pulsing = true }
        }
    }
}

// MARK: - Benchmark Delta Neon Badge
struct DeltaBadge: View {
    let current: Double
    let previous: Double?
    var lowerIsBetter: Bool = false

    var body: some View {
        if let prev = previous, prev > 0 {
            let pct = ((current - prev) / prev) * 100.0
            if abs(pct) >= 1.0 {
                let improved = lowerIsBetter ? (pct < 0) : (pct > 0)
                let color: Color = improved ? HudTheme.emerald : HudTheme.amber
                let arrow = pct > 0 ? "▲" : "▼"
                Text("\(arrow)\(String(format: "%.0f%%", abs(pct)))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(color.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.7))
                    .foregroundStyle(color)
            }
        }
    }
}
