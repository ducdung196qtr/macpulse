import SwiftUI
import MacPulseCore

struct DashboardView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                metricsGrid

                if let pending = vm.pendingTerminationGroup {
                    InlineConfirmTerminationCard(group: pending, vm: vm)
                }

                if vm.showTabInspector {
                    BrowserTabsInspectorCard(vm: vm)
                }

                findingsSection
                topProcessesSection
            }
            .padding(14)
        }
    }

    private var metricsGrid: some View {
        HStack(spacing: 8) {
            if let snap = vm.snapshot {
                MetricTile(
                    icon: "cpu",
                    title: "CPU",
                    value: String(format: "%.0f%%", snap.cpu.totalBusyPercent),
                    subtitle: String(format: "User %.0f%% • Sys %.0f%%", snap.cpu.userPercent, snap.cpu.systemPercent),
                    progress: min(1.0, snap.cpu.totalBusyPercent / 100.0),
                    color: snap.cpu.totalBusyPercent >= 70 ? .red : (snap.cpu.totalBusyPercent >= 40 ? .orange : .green)
                )

                Button {
                    vm.cleanerFocus = .ram
                    vm.selectedTab = .cleaner
                } label: {
                    MetricTile(
                        icon: "memorychip",
                        title: "RAM Trống",
                        value: String(format: "%.1f GB", snap.memory.availableGB),
                        subtitle: String(format: "Nén %.1fG • Swap %.1fG", snap.memory.compressedGB, snap.memory.swapUsedGB),
                        progress: min(1.0, snap.memory.usedPercent / 100.0),
                        color: snap.memory.compressedGB >= 5.0 ? .red : (snap.memory.compressedGB >= 3.5 ? .orange : .blue)
                    )
                }
                .buttonStyle(.plain)
                .help("Bấm để mở mục Giải phóng RAM")

                Button {
                    vm.cleanerFocus = .all
                    vm.selectedTab = .cleaner
                } label: {
                    MetricTile(
                        icon: "internaldrive",
                        title: "SSD Trống",
                        value: String(format: "%.1f GB", snap.disk.availableGB),
                        subtitle: String(format: "Tổng %.0f GB", snap.disk.totalGB),
                        progress: min(1.0, snap.disk.usedPercent / 100.0),
                        color: snap.disk.availableGB < 20 ? .red : (snap.disk.availableGB < 32 ? .orange : .green)
                    )
                }
                .buttonStyle(.plain)
                .help("Bấm để mở mục Dọn Cache & SSD")
            } else {
                ProgressView("Đang đọc chỉ số máy...")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var findingsSection: some View {
        if let report = vm.healthReport {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(report.findings.isEmpty ? "Tình trạng hệ thống" : "Cần xử lý để hết giật / nặng")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !report.findings.isEmpty {
                        Text("\(report.findings.count) cảnh báo")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if report.findings.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("CPU, RAM và SSD đều thông thoáng — không có dấu hiệu nghẽn.")
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ForEach(report.findings) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: item.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(item.severity == .critical ? .red : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if !item.impactNote.isEmpty {
                                        Text(item.impactNote)
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                if item.recommendedAction != .none {
                                    Button(item.actionLabel ?? "Xử lý") {
                                        vm.performRecommendedAction(item.recommendedAction, targetID: item.targetID)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(item.severity == .critical ? .red : .orange)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(10)
                        .background(
                            (item.severity == .critical ? Color.red : Color.orange).opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }
            }
        }
    }

    private var topProcessesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tiến trình & App đang chạy")
                        .font(.subheadline.weight(.semibold))
                    Text("Rê chuột vào ⓘ để xem đang làm gì & an toàn tắt")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(vm.isScanningTabs ? "Đang quét..." : "Soi tab Chrome") {
                    vm.scanBrowserTabs()
                }
                .controlSize(.small)
                .disabled(vm.isScanningTabs)
            }

            // Search bar & category filter chips
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Tìm kiếm app, tiến trình hoặc PID...", text: $vm.processSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !vm.processSearchQuery.isEmpty {
                        Button {
                            vm.processSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Category chips
                HStack(spacing: 4) {
                    ForEach(ProcessFilterCategory.allCases) { cat in
                        let active = vm.processCategoryFilter == cat
                        Button {
                            vm.processCategoryFilter = cat
                        } label: {
                            Text(cat.rawValue)
                                .font(.system(size: 10, weight: active ? .semibold : .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(active ? Color.accentColor : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(active ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let displayList = vm.filteredProcessGroups.prefix(12)
            if displayList.isEmpty {
                Text("Không tìm thấy tiến trình nào khớp bộ lọc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 6) {
                    ForEach(displayList) { group in
                        ProcessRowView(group: group, vm: vm, highlightRAM: false)
                    }
                }
            }
        }
    }
}

private struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(max(0, min(1, progress)))))
                }
            }
            .frame(height: 4)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
