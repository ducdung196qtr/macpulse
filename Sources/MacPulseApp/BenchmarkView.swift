import SwiftUI
import MacPulseCore

struct BenchmarkView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Đo hiệu năng thực tế (CPU / RAM / SSD)")
                            .font(.headline)
                        Text(vm.benchmarkStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(vm.isBenchmarkRunning ? "Đang đo..." : "Chạy Benchmark") {
                        vm.runBenchmark()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isBenchmarkRunning)
                }

                if let err = vm.benchmarkError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                if let res = vm.latestBenchmark {
                    VStack(spacing: 8) {
                        BenchRow(
                            icon: "cpu",
                            label: "CPU Single-Core",
                            value: String(format: "%.0f M ops/s", res.cpuSingleOpsPerSec / 1_000_000),
                            baseline: "M2 chuẩn ~550-850 M ops/s",
                            ratio: res.cpuSingleOpsPerSec / 750_000_000,
                            ok: res.cpuSingleOpsPerSec > 400_000_000
                        )
                        BenchRow(
                            icon: "cpu.fill",
                            label: "CPU Multi-Core",
                            value: String(format: "%.0f M ops/s", res.cpuMultiOpsPerSec / 1_000_000),
                            baseline: "M2 8-core ~2500-4500 M ops/s",
                            ratio: res.cpuMultiOpsPerSec / 3_500_000_000,
                            ok: res.cpuMultiOpsPerSec > 1_800_000_000
                        )
                        BenchRow(
                            icon: "memorychip",
                            label: "Băng thông RAM",
                            value: String(format: "%.1f GB/s", res.memoryBandwidthGBs),
                            baseline: "M2 LPDDR5 ~45-95 GB/s",
                            ratio: res.memoryBandwidthGBs / 75.0,
                            ok: res.memoryBandwidthGBs > 30
                        )
                        BenchRow(
                            icon: "internaldrive",
                            label: "SSD Ghi tuần tự",
                            value: String(format: "%.0f MB/s", res.diskWriteMBs),
                            baseline: "M2 256GB ~1200-1700 MB/s (chậm nếu SSD < 20 GB trống)",
                            ratio: res.diskWriteMBs / 1500.0,
                            ok: res.diskWriteMBs > 600
                        )
                        BenchRow(
                            icon: "internaldrive.fill",
                            label: "SSD Đọc tuần tự",
                            value: String(format: "%.0f MB/s", res.diskReadMBs),
                            baseline: "M2 256GB ~1400-2000 MB/s",
                            ratio: res.diskReadMBs / 1700.0,
                            ok: res.diskReadMBs > 700
                        )
                        if let ms = res.localWPLatencyMs, let code = res.localWPStatusCode {
                            BenchRow(
                                icon: "globe",
                                label: "Local WordPress",
                                value: String(format: "%.0f ms (HTTP %d)", ms, code),
                                baseline: "Bình thường < 500 ms",
                                ratio: max(0.15, min(1.0, 500.0 / max(100.0, ms))),
                                ok: ms < 800 && code < 500
                            )
                        }
                    }
                } else {
                    Text("Chưa có kết quả đo. Bấm 'Chạy Benchmark' để kiểm tra tốc độ thực của Mac Mini M2 (mất ~2-3 giây).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                if vm.benchmarkHistory.count > 1 {
                    HStack {
                        Text("Lịch sử gần đây")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Xoá lịch sử") {
                            vm.clearBenchmarkHistory()
                        }
                        .controlSize(.mini)
                    }
                    ForEach(vm.benchmarkHistory.dropFirst().prefix(5)) { old in
                        HStack {
                            Text(old.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "SSD W %.0f / R %.0f MB/s • RAM %.0f GB/s", old.diskWriteMBs, old.diskReadMBs, old.memoryBandwidthGBs))
                                .font(.caption2.monospacedDigit())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct BenchRow: View {
    let icon: String
    let label: String
    let value: String
    let baseline: String
    let ratio: Double
    let ok: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(ok ? .green : .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.subheadline.weight(.medium))
                    Text(baseline).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(value)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(ok ? .green : .orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(ok ? Color.green : Color.orange)
                        .frame(width: max(6, geo.size.width * CGFloat(max(0.08, min(1.0, ratio)))))
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
