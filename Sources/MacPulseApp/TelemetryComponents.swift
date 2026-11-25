import SwiftUI
import MacPulseCore

// MARK: - Tactical Sci-Fi Section Header
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

            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(HudTheme.textSecondary)

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

// MARK: - Single-Canvas Arc Reactor Health Gauge (Zero offscreen shadows, 0% idle CPU)
struct ArcHealthGauge: View {
    let score: Int
    let color: Color
    var size: CGFloat = 44

    private var progress: Double {
        max(0, min(1, Double(score) / 100.0))
    }

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let radius = min(sz.width, sz.height) / 2

                // 24 radar dial ticks drawn in a single vector pass
                var majorPath = Path()
                var minorPath = Path()
                for idx in 0..<24 {
                    let angle = CGFloat(idx) * (.pi * 2 / 24)
                    let isMajor = (idx % 6 == 0)
                    let outerR = radius - 0.5
                    let innerR = radius - (isMajor ? radius * 0.19 : radius * 0.11)
                    let p1 = CGPoint(x: center.x + cos(angle) * innerR, y: center.y + sin(angle) * innerR)
                    let p2 = CGPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR)
                    if isMajor {
                        majorPath.move(to: p1); majorPath.addLine(to: p2)
                    } else {
                        minorPath.move(to: p1); minorPath.addLine(to: p2)
                    }
                }
                ctx.stroke(minorPath, with: .color(HudTheme.textMuted.opacity(0.32)), lineWidth: 0.75)
                ctx.stroke(majorPath, with: .color(color.opacity(0.65)), lineWidth: 1.2)

                // Inner dashed orbital ring
                let innerR = radius * 0.62
                let innerRect = CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2)
                ctx.stroke(Path(ellipseIn: innerRect), with: .color(color.opacity(0.24)), style: StrokeStyle(lineWidth: 0.85, dash: [2.5, 3]))

                // Track arc (270 deg: 135° -> 405°)
                let arcR = radius * 0.80
                let lineW = max(3.0, size * 0.105)
                var track = Path()
                track.addArc(center: center, radius: arcR, startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                ctx.stroke(track, with: .color(HudTheme.insetBg), style: StrokeStyle(lineWidth: lineW, lineCap: .round))

                // Active energy arc: outer soft neon bloom + crisp core (0 GPU shadow pass)
                if progress > 0.001 {
                    let endDeg = 135.0 + 270.0 * progress
                    var active = Path()
                    active.addArc(center: center, radius: arcR, startAngle: .degrees(135), endAngle: .degrees(endDeg), clockwise: false)
                    ctx.stroke(active, with: .color(color.opacity(0.24)), style: StrokeStyle(lineWidth: lineW + 3.5, lineCap: .round))
                    ctx.stroke(active, with: .color(color), style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                }
            }

            Text("\(score)")
                .font(.system(size: size * 0.31, weight: .black, design: .monospaced))
                .foregroundStyle(HudTheme.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Single-Canvas Neon Oscilloscope (Zero Blur / Zero Shadow — 120fps Smooth)
struct LiveSparklineView: View {
    let samples: [Double]
    let color: Color
    var maxValue: Double = 100.0
    var height: CGFloat = 26

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width
            let h = sz.height
            guard w > 4, h > 4 else { return }

            let bgRect = CGRect(origin: .zero, size: sz)
            let bgPath = Path(roundedRect: bgRect, cornerRadius: 4)
            ctx.fill(bgPath, with: .color(HudTheme.insetBg.opacity(0.92)))
            ctx.stroke(bgPath, with: .color(color.opacity(0.18)), lineWidth: 0.6)

            // Micro gridlines
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: h * 0.5))
            grid.addLine(to: CGPoint(x: w, y: h * 0.5))
            grid.move(to: CGPoint(x: w * 0.5, y: 0))
            grid.addLine(to: CGPoint(x: w * 0.5, y: h))
            ctx.stroke(grid, with: .color(color.opacity(0.10)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

            let pts: [Double] = samples.count >= 2 ? samples : [samples.first ?? 0, samples.first ?? 0]
            let stepX = w / CGFloat(max(1, pts.count - 1))

            var line = Path()
            var fill = Path()
            var lastPoint = CGPoint(x: w - 2, y: h - 2)

            for (i, val) in pts.enumerated() {
                let norm = max(0.05, min(0.95, val / max(1.0, maxValue)))
                let pt = CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat(norm) * (h - 4) - 2)
                lastPoint = pt
                if i == 0 {
                    line.move(to: pt)
                    fill.move(to: CGPoint(x: pt.x, y: h))
                    fill.addLine(to: pt)
                } else {
                    line.addLine(to: pt)
                    fill.addLine(to: pt)
                }
            }
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.closeSubpath()

            ctx.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.34), color.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: h)
                )
            )

            // Pure vector neon bloom (2 strokes: wide translucent halo + sharp bright core, 0 blur cost)
            ctx.stroke(line, with: .color(color.opacity(0.24)), style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Concentric glowing live node (0 shadow cost)
            let haloRect = CGRect(x: lastPoint.x - 4.5, y: lastPoint.y - 4.5, width: 9, height: 9)
            let coreRect = CGRect(x: lastPoint.x - 2, y: lastPoint.y - 2, width: 4, height: 4)
            ctx.fill(Path(ellipseIn: haloRect), with: .color(color.opacity(0.32)))
            ctx.fill(Path(ellipseIn: coreRect), with: .color(Color.white))
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Single-Canvas Segmented Memory Allocation Bar
struct SegmentedMemoryBar: View {
    let memory: MemoryMetrics
    var height: CGFloat = 5.5

    var body: some View {
        Canvas { ctx, sz in
            let total = max(1.0, Double(memory.totalBytes))
            let appFrac = min(1.0, Double(memory.effectiveAppMemoryBytes) / total)
            let wiredFrac = min(1.0 - appFrac, Double(memory.wiredBytes) / total)
            let compFrac = min(1.0 - appFrac - wiredFrac, Double(memory.compressedBytes) / total)
            let cacheFrac = min(1.0 - appFrac - wiredFrac - compFrac, Double(memory.cachedFilesBytes) / total)

            let bg = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 2.5)
            ctx.fill(bg, with: .color(HudTheme.insetBg))

            let segments: [(Double, Color)] = [
                (appFrac, HudTheme.cyan),
                (wiredFrac, HudTheme.cobalt),
                (compFrac, HudTheme.amber),
                (cacheFrac, HudTheme.teal.opacity(0.55))
            ]

            var curX: CGFloat = 0
            for (frac, col) in segments where frac > 0.005 {
                let segW = max(2, sz.width * CGFloat(frac) - 1.2)
                let rect = CGRect(x: curX, y: 0, width: min(segW, sz.width - curX), height: sz.height)
                ctx.fill(Path(rect), with: .color(col))
                curX += segW + 1.2
                if curX >= sz.width { break }
            }
            ctx.stroke(bg, with: .color(HudTheme.cyan.opacity(0.18)), lineWidth: 0.5)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2.5))
    }
}

// MARK: - Single-Canvas Holographic LED Segmented Bar (1 Draw Call instead of 24 Shadow Views!)
struct TickProgressBar: View {
    let ratio: Double // 0...1
    let color: Color
    var height: CGFloat = 6.5
    var showTicks: Bool = true
    var segments: Int = 20

    var body: some View {
        Canvas { ctx, sz in
            let clamped = max(0, min(1, ratio))
            let segCount = max(4, segments)
            let gap: CGFloat = 2.0
            let segW = (sz.width - gap * CGFloat(segCount - 1)) / CGFloat(segCount)
            guard segW > 1 else { return }
            let litCount = Int((clamped * Double(segCount)).rounded(.up))

            for idx in 0..<segCount {
                let x = CGFloat(idx) * (segW + gap)
                let rect = CGRect(x: x, y: 0, width: segW, height: sz.height)
                let path = Path(roundedRect: rect, cornerRadius: 1.5)
                let isLit = clamped > 0.001 && idx < litCount
                if isLit {
                    let cellColor = (idx == litCount - 1) ? Color.white.opacity(0.92) : color
                    ctx.fill(path, with: .color(cellColor))
                } else {
                    ctx.fill(path, with: .color(HudTheme.insetBg))
                    ctx.stroke(path, with: .color(color.opacity(0.14)), lineWidth: 0.5)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Single-Canvas Orbital Hologram Quota Ring (Zero Shadow Pass)
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
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let radius = min(sz.width, sz.height) / 2

                // Outer orbital dashed circle
                let outerRect = CGRect(x: 0.6, y: 0.6, width: sz.width - 1.2, height: sz.height - 1.2)
                ctx.stroke(Path(ellipseIn: outerRect), with: .color(color.opacity(0.20)), style: StrokeStyle(lineWidth: 0.75, dash: [2, 3]))

                // Track ring
                let arcR = radius * 0.80
                var track = Path()
                track.addArc(center: center, radius: arcR, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                ctx.stroke(track, with: .color(HudTheme.insetBg), style: StrokeStyle(lineWidth: lineWidth))

                // Active arc with vector halo
                if frac > 0.001 {
                    var active = Path()
                    active.addArc(center: center, radius: arcR, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * frac), clockwise: false)
                    ctx.stroke(active, with: .color(color.opacity(0.24)), style: StrokeStyle(lineWidth: lineWidth + 3.0, lineCap: .round))
                    ctx.stroke(active, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }

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

// MARK: - Zero-CPU Static Holographic Telemetry Beacon (Replaced 60fps repeatForever loop!)
struct LivePulseDot: View {
    let color: Color
    var isLive: Bool = true

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 11, height: 11)
                Circle()
                    .stroke(color.opacity(0.55), lineWidth: 0.8)
                    .frame(width: 11, height: 11)
            }
            Circle()
                .fill(color)
                .frame(width: 5.5, height: 5.5)
        }
        .frame(width: 11, height: 11)
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
