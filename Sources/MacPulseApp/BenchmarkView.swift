import SwiftUI
import MacPulseCore

struct BenchmarkView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerLabCard

                if let err = vm.benchmarkError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(PulseTheme.crimson)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(PulseTheme.crimson)
                    }
                    .telemetryCard(accent: PulseTheme.crimson, cornerRadius: 9, padding: 9)
                }

                if let res = vm.latestBenchmark {
                    let prev = vm.previousBenchmark
                    let cores = vm.hardwareSpecs.coreCount
                    let diskLabel = "\(vm.hardwareSpecs.totalDiskGB)GB SSD"

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
                            .font(.system(size: 26))
                            .foregroundStyle(PulseTheme.cyan)
                        Text("Chưa có dữ liệu đo hiệu năng")
                            .font(.subheadline.weight(.semibold))
                        Text("Bấm \"Chạy Benchmark\" để đo thực tế CPU đa nhân, băng thông RAM và tốc độ đọc/ghi trực tiếp SSD (F_NOCACHE) trong ~2 giây.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .telemetryCard(cornerRadius: 11, padding: 20)
                }

                if vm.benchmarkHistory.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionEyebrow(
                                icon: "clock.arrow.circlepath",
                                title: "Lịch sử đo (\(vm.benchmarkHistory.count) lần)",
                                color: PulseTheme.cobalt
                            )
                            Button("Xoá lịch sử") {
                                vm.clearBenchmarkHistory()
                            }
                            .controlSize(.mini)
                        }

                        ForEach(vm.benchmarkHistory.dropFirst().prefix(5)) { old in
                            let oldScore = BenchmarkRunner.compositeScore(for: old)
                            HStack(spacing: 8) {
                                Text("\(oldScore)")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 2)
                                    .background(PulseTheme.cyan.opacity(0.14), in: Capsule())
                                    .foregroundStyle(PulseTheme.cyan)
                                Text(old.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "W %.0f / R %.0f MB/s • RAM %.0f GB/s", old.diskWriteMBs, old.diskReadMBs, old.memoryBandwidthGBs))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
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
                        color: score >= 75 ? PulseTheme.emerald : (score >= 50 ? PulseTheme.cyan : PulseTheme.amber),
                        size: 52
                    )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(PulseTheme.cyan.opacity(0.16))
                            .frame(width: 46, height: 46)
                        Image(systemName: "speedometer")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(PulseTheme.cyan)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Phòng đo Hiệu năng Thực tế")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("\(vm.hardwareSpecs.compactBadge) • \(vm.benchmarkStatus)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    vm.runBenchmark()
                } label: {
                    HStack(spacing: 5) {
                        if vm.isBenchmarkRunning {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                        }
                        Text(vm.isBenchmarkRunning ? "Đang đo..." : "Chạy Benchmark")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.cobalt)
                .controlSize(.small)
                .disabled(vm.isBenchmarkRunning)
            }

            if !vm.availableLocalSites.isEmpty {
                Divider().opacity(0.4)
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundStyle(PulseTheme.cyan)
                    Text("Đo thêm độ trễ LocalWP:")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $vm.selectedLocalSiteForBench) {
                        Text("Tắt (Nhanh nhất)").tag("")
                        ForEach(vm.availableLocalSites, id: \.self) { site in
                            Text("\(site).local").tag(site)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 180)
                    Spacer()
                }
            }
        }
        .telemetryCard(accent: PulseTheme.cobalt, cornerRadius: 12, padding: 12)
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
        ok ? PulseTheme.emerald : PulseTheme.amber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                    Text(baseline)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    DeltaBadge(current: currentRaw, previous: previousRaw, lowerIsBetter: lowerIsBetter)
                    Text(value)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                }
            }

            TickProgressBar(
                ratio: max(0.08, min(1.0, ratio)),
                color: accentColor,
                height: 5.5,
                showTicks: true
            )
        }
        .telemetryCard(accent: accentColor, cornerRadius: 10, padding: 10)
    }
}
