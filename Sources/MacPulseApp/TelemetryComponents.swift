import SwiftUI
import MacPulseCore

// MARK: - Section Eyebrow Header
struct SectionEyebrow: View {
    let icon: String
    let title: String
    var color: Color = PulseTheme.cyan
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Arc Health Gauge (Precision Cockpit Ring)
struct ArcHealthGauge: View {
    let score: Int
    let color: Color
    var size: CGFloat = 38

    private var progress: Double {
        max(0, min(1, Double(score) / 100.0))
    }

    var body: some View {
        ZStack {
            // Subtle micro-ticks around arc
            ForEach(0..<15, id: \.self) { idx in
                let angle = -225.0 + (Double(idx) / 14.0) * 270.0
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: 1, height: size * 0.08)
                    .offset(y: -size * 0.48)
                    .rotationEffect(.degrees(angle))
            }

            // Track arc
            Circle()
                .trim(from: 0.125, to: 0.875)
                .stroke(
                    Color.primary.opacity(0.11),
                    style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            // Active glowing progress arc
            Circle()
                .trim(from: 0.125, to: 0.125 + 0.75 * progress)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.65), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(300)
                    ),
                    style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .shadow(color: color.opacity(0.45), radius: 3)
                .animation(.easeOut(duration: 0.45), value: progress)

            Text("\(score)")
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Live Sparkline Chart (Zero-dependency SwiftUI Path)
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
                // Micro telemetry horizontal grid lines
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.5))
                    p.addLine(to: CGPoint(x: w, y: h * 0.5))
                    p.move(to: CGPoint(x: 0, y: h - 0.5))
                    p.addLine(to: CGPoint(x: w, y: h - 0.5))
                }
                .stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))

                // Gradient area fill under curve
                Path { path in
                    for (i, val) in pts.enumerated() {
                        let norm = max(0.02, min(1.0, val / max(1.0, maxValue)))
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
                        colors: [color.opacity(0.28), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Crisp waveform line
                Path { path in
                    for (i, val) in pts.enumerated() {
                        let norm = max(0.02, min(1.0, val / max(1.0, maxValue)))
                        let x = CGFloat(i) * stepX
                        let y = h - CGFloat(norm) * (h - 4) - 2
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Live endpoint beacon
                if let last = pts.last {
                    let norm = max(0.02, min(1.0, last / max(1.0, maxValue)))
                    let y = h - CGFloat(norm) * (h - 4) - 2
                    Circle()
                        .fill(color)
                        .frame(width: 4.5, height: 4.5)
                        .shadow(color: color.opacity(0.8), radius: 3)
                        .position(x: w - 1, y: y)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Segmented Memory Allocation Bar (Activity Monitor Precision)
struct SegmentedMemoryBar: View {
    let memory: MemoryMetrics
    var height: CGFloat = 6

    var body: some View {
        let total = max(1.0, Double(memory.totalBytes))
        let appFrac = min(1.0, Double(memory.effectiveAppMemoryBytes) / total)
        let wiredFrac = min(1.0 - appFrac, Double(memory.wiredBytes) / total)
        let compFrac = min(1.0 - appFrac - wiredFrac, Double(memory.compressedBytes) / total)
        let cacheFrac = min(1.0 - appFrac - wiredFrac - compFrac, Double(memory.cachedFilesBytes) / total)

        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))

                HStack(spacing: 1) {
                    if appFrac > 0.005 {
                        Rectangle()
                            .fill(PulseTheme.cyan)
                            .frame(width: max(2, w * CGFloat(appFrac)))
                    }
                    if wiredFrac > 0.005 {
                        Rectangle()
                            .fill(PulseTheme.cobalt)
                            .frame(width: max(2, w * CGFloat(wiredFrac)))
                    }
                    if compFrac > 0.005 {
                        Rectangle()
                            .fill(PulseTheme.amber)
                            .frame(width: max(2, w * CGFloat(compFrac)))
                    }
                    if cacheFrac > 0.005 {
                        Rectangle()
                            .fill(PulseTheme.teal.opacity(0.45))
                            .frame(width: max(2, w * CGFloat(cacheFrac)))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
    }
}

// MARK: - Scientific Tick-Marked Progress Bar
struct TickProgressBar: View {
    let ratio: Double // 0...1
    let color: Color
    var height: CGFloat = 7
    var showTicks: Bool = true

    var body: some View {
        let clamped = max(0, min(1, ratio))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.primary.opacity(0.09))

                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.75), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(clamped > 0 ? 4 : 0, geo.size.width * CGFloat(clamped)))
                    .shadow(color: color.opacity(0.35), radius: 2)
                    .animation(.easeOut(duration: 0.35), value: clamped)

                if showTicks {
                    HStack(spacing: 0) {
                        ForEach(1..<4, id: \.self) { i in
                            Spacer()
                            Rectangle()
                                .fill(Color.black.opacity(0.25))
                                .frame(width: 1, height: height)
                            if i == 3 { Spacer() }
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Precision Quota Ring
struct QuotaRingView: View {
    let remainingPercent: Double
    let color: Color
    var size: CGFloat = 46
    var lineWidth: CGFloat = 4.5

    private var frac: Double {
        max(0, min(1, remainingPercent / 100.0))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: frac)
                .stroke(
                    LinearGradient(colors: [color.opacity(0.7), color], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: 2.5)
                .animation(.easeOut(duration: 0.4), value: frac)

            VStack(spacing: -1) {
                Text("\(Int(remainingPercent.rounded()))")
                    .font(.system(size: size * 0.31, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text("%")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Live Signal Pulse Dot
struct LivePulseDot: View {
    let color: Color
    var isLive: Bool = true
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulsing ? 1.35 : 0.7)
                    .opacity(pulsing ? 0.0 : 0.7)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulsing)
            }
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
        .onAppear {
            if isLive { pulsing = true }
        }
    }
}

// MARK: - Benchmark Delta Badge
struct DeltaBadge: View {
    let current: Double
    let previous: Double?
    var lowerIsBetter: Bool = false

    var body: some View {
        if let prev = previous, prev > 0 {
            let pct = ((current - prev) / prev) * 100.0
            if abs(pct) >= 1.0 {
                let improved = lowerIsBetter ? (pct < 0) : (pct > 0)
                let color: Color = improved ? PulseTheme.emerald : PulseTheme.amber
                let arrow = pct > 0 ? "▲" : "▼"
                Text("\(arrow) \(String(format: "%.0f%%", abs(pct)))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }
        }
    }
}
