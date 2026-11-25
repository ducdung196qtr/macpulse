import SwiftUI
import MacPulseCore

struct BenchmarkView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                headerLabCard

                if let err = vm.benchmarkError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(HudTheme.crimson)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(HudTheme.crimson)
                    }
                    .hudCard(accent: HudTheme.crimson, chamfer: 8, padding: 9)
                }

                if let res = vm.latestBenchmark {
                    let prev = vm.previousBenchmark
                    let cores = vm.hardwareSpecs.coreCount
                    let diskLabel = "\(vm.hardwareSpecs.totalDiskGB)GB NVMe SSD"

                    VStack(spacing: 8) {
                        BenchLabRow(
                            icon: "cpu",
                            label: "CPU Đơn nhân (Single-Core)",
                            value: String(format: "%.0f M ops/s", res.cpuSingleOpsPerSec / 1_000_000),
                            baseline: "Tham chiếu Apple Silicon ~550–850 M ops/s",
                            ratio: res.cpuSingleOpsPerSec / 750_000_000,
                            ok: res.cpuSingleOpsPerSec > 400_000_000,
                            currentRaw: res.cpuSingleOpsPerSec,
                            previousRaw: prev?.cpuSingleOpsPerSec
                        )
                        BenchLabRow(
                            icon: "cpu.fill",
                            label: "CPU Đa nhân (\(cores)-Core)",
                            value: String(format: "%.0f M ops/s", res.cpuMultiOpsPerSec / 1_000_000),
                            baseline: "Tham chiếu \(cores)-core ~\(cores * 320)–\(cores * 550) M ops/s",
                            ratio: res.cpuMultiOpsPerSec / Double(max(1, cores) * 440_000_000),
                            ok: res.cpuMultiOpsPerSec > Double(max(1, cores) * 220_000_000),
                            currentRaw: res.cpuMultiOpsPerSec,
                            previousRaw: prev?.cpuMultiOpsPerSec
                        )
                        BenchLabRow(
                            icon: "memorychip",
                            label: "Băng thông RAM (Unified Memory)",
                            value: String(format: "%.1f GB/s", res.memoryBandwidthGBs),
                            baseline: "\(vm.hardwareSpecs.totalRAMGB)GB Unified • Tham chiếu ~45–95 GB/s",
                            ratio: res.memoryBandwidthGBs / 75.0,
                            ok: res.memoryBandwidthGBs > 30,
                            currentRaw: res.memoryBandwidthGBs,
                            previousRaw: prev?.memoryBandwidthGBs
                        )
                        BenchLabRow(
                            icon: "internaldrive",
                            label: "SSD Ghi tuần tự (F_NOCACHE)",
                            value: String(format: "%.0f MB/s", res.diskWriteMBs),
                            baseline: "\(diskLabel) • Chậm rõ nếu trống < 20 GB",
                            ratio: res.diskWriteMBs / 1500.0,
                            ok: res.diskWriteMBs > 600,
                            currentRaw: res.diskWriteMBs,
                            previousRaw: prev?.diskWriteMBs
                        )
                        BenchLabRow(
                            icon: "internaldrive.fill",
                            label: "SSD Đọc tuần tự (F_NOCACHE)",
                            value: String(format: "%.0f MB/s", res.diskReadMBs),
                            baseline: "\(diskLabel) • Chuẩn ~1400–2500 MB/s",
                            ratio: res.diskReadMBs / 1700.0,
                            ok: res.diskReadMBs > 700,
                            currentRaw: res.diskReadMBs,
                            previousRaw: prev?.diskReadMBs
                        )
                        if let ms = res.localWPLatencyMs, let code = res.localWPStatusCode {
                            BenchLabRow(
                                icon: "globe",
                                label: "LocalWP HTTP (\(vm.selectedLocalSiteForBench.isEmpty ? "Local" : vm.selectedLocalSiteForBench).local)",
                                value: String(format: "%.0f ms (HTTP %d)", ms, code),
                                baseline: "Mượt < 500 ms",
                                ratio: max(0.15, min(1.0, 500.0 / max(100.0, ms))),
                                ok: ms < 800 && code < 500,
                                currentRaw: ms,
                                previousRaw: prev?.localWPLatencyMs,
                                lowerIsBetter: true
                            )
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 28))
                            .foregroundStyle(HudTheme.cyan)
                        Text("SẴN SÀNG ĐO HIỆU NĂNG PHẦN CỨNG")
                            .font(.system(size: 11.5, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.textPrimary)
                        Text("Bấm \"Chạy Benchmark\" để đo thực tế CPU đa nhân, băng thông RAM và tốc độ đọc/ghi trực tiếp SSD (F_NOCACHE) trong ~2 giây.")
                            .font(.caption2)
                            .foregroundStyle(HudTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .hudCard(accent: HudTheme.cyan, chamfer: 10, padding: 20, showBrackets: true)
                }

                if vm.benchmarkHistory.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionEyebrow(
                                icon: "clock.arrow.circlepath",
                                title: "Nhật ký đo hiệu năng",
                                color: HudTheme.cobalt,
                                trailingText: "\(vm.benchmarkHistory.count) LẦN"
                            )
                            HudButton(title: "Xoá lịch sử", color: HudTheme.crimson, filled: false, compact: true) {
                                vm.clearBenchmarkHistory()
                            }
                        }

                        ForEach(vm.benchmarkHistory.dropFirst().prefix(5)) { old in
                            let oldScore = BenchmarkRunner.compositeScore(for: old)
                            HStack(spacing: 8) {
                                Text("\(oldScore)")
                                    .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(HudTheme.cyan.opacity(0.16), in: Capsule())
                                    .overlay(Capsule().strokeBorder(HudTheme.cyan.opacity(0.4), lineWidth: 0.6))
                                    .foregroundStyle(HudTheme.cyan)
                                Text(old.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(HudTheme.textSecondary)
                                Spacer()
                                Text(String(format: "W %.0f / R %.0f MB/s • RAM %.0f GB/s", old.diskWriteMBs, old.diskReadMBs, old.memoryBandwidthGBs))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(HudTheme.textPrimary.opacity(0.85))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6.5)
                            .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.cobalt.opacity(0.22), lineWidth: 0.6))
                        }
                    }
                }
            }
            .padding(14)
        }
        .onAppear {
            vm.refreshLocalSites()
        }
    }

    // MARK: - Lab Header Card
    private var headerLabCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let res = vm.latestBenchmark {
                    let score = BenchmarkRunner.compositeScore(for: res)
                    ArcHealthGauge(
                        score: score,
                        color: score >= 75 ? HudTheme.emerald : (score >= 50 ? HudTheme.cyan : HudTheme.amber),
                        size: 54
                    )
                } else {
                    ZStack {
                        ChamferedRect(cut: 7, cornerRadius: 3)
                            .fill(HudTheme.cyan.opacity(0.18))
                            .overlay(ChamferedRect(cut: 7, cornerRadius: 3).strokeBorder(HudTheme.cyan.opacity(0.55), lineWidth: 0.8))
                            .frame(width: 46, height: 46)
                        Image(systemName: "speedometer")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(HudTheme.cyan)
                    }
                }

                VStack(alignment: .leading, spacing: 2.5) {
                    Text("HARDWARE BENCHMARK LAB")
                        .font(.system(size: 12.5, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(HudTheme.textPrimary)
                    Text("\(vm.hardwareSpecs.compactBadge) • \(vm.benchmarkStatus)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                }

                Spacer()

                HudButton(
                    title: vm.isBenchmarkRunning ? "Đang đo..." : "Chạy Benchmark",
                    icon: "play.fill",
                    color: HudTheme.cyan,
                    filled: true,
                    compact: false,
                    disabled: vm.isBenchmarkRunning
                ) {
                    vm.runBenchmark()
                }
            }

            if !vm.availableLocalSites.isEmpty {
                Rectangle().fill(HudTheme.cyan.opacity(0.2)).frame(height: 0.7)
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.cyan)
                    Text("ĐO THÊM LOCALWP:")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)

                    Menu {
                        Button("Tắt (Nhanh nhất)") { vm.selectedLocalSiteForBench = "" }
                        Divider()
                        ForEach(vm.availableLocalSites, id: \.self) { site in
                            Button("\(site).local") { vm.selectedLocalSiteForBench = site }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(vm.selectedLocalSiteForBench.isEmpty ? "Tắt (Nhanh nhất)" : "\(vm.selectedLocalSiteForBench).local")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(HudTheme.cyan)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(HudTheme.textSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(HudTheme.cyan.opacity(0.35), lineWidth: 0.75))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()
                }
            }
        }
        .hudCard(accent: HudTheme.cyan, chamfer: 10, padding: 12, showBrackets: true)
    }
}

private struct BenchLabRow: View {
    let icon: String
    let label: String
    let value: String
    let baseline: String
    let ratio: Double
    let ok: Bool
    let currentRaw: Double
    let previousRaw: Double?
    var lowerIsBetter: Bool = false

    private var accentColor: Color {
        ok ? HudTheme.emerald : HudTheme.amber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6.5) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text(baseline)
                        .font(.system(size: 9.5))
                        .foregroundStyle(HudTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    DeltaBadge(current: currentRaw, previous: previousRaw, lowerIsBetter: lowerIsBetter)
                    Text(value)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(accentColor)
                }
            }

            TickProgressBar(
                ratio: max(0.08, min(1.0, ratio)),
                color: accentColor,
                height: 6,
                showTicks: true,
                segments: 24
            )
        }
        .hudCard(accent: accentColor, chamfer: 8, padding: 10, showBrackets: false)
    }
}
