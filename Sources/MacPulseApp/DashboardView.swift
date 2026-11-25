import SwiftUI
import MacPulseCore

struct DashboardView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                aiQuotaMiniStrip
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

    // MARK: - AI Quota Live Mini-Strip
    @ViewBuilder
    private var aiQuotaMiniStrip: some View {
        if let ai = vm.aiSnapshot, (ai.antigravity?.isDetected == true || ai.chatGPT?.isDetected == true) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    vm.selectedTab = .aiPulse
                }
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        LivePulseDot(
                            color: (ai.antigravity?.sourceState == .live || ai.chatGPT?.sourceState == .live) ? PulseTheme.emerald : PulseTheme.amber,
                            isLive: ai.antigravity?.sourceState == .live || ai.chatGPT?.sourceState == .live
                        )
                        Text("AI QUOTA")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 14)

                    if let agy = ai.antigravity, agy.isDetected, let q5 = agy.fiveHourQuota {
                        miniQuotaChip(
                            label: "AGY 5h",
                            remainingPct: q5.remainingPercent,
                            color: PulseTheme.cobalt
                        )
                    }

                    if let gpt = ai.chatGPT, gpt.isDetected {
                        if let q5 = gpt.fiveHourQuota {
                            miniQuotaChip(
                                label: "GPT 5h",
                                remainingPct: q5.remainingPercent,
                                color: PulseTheme.emerald
                            )
                        }
                        if let q7 = gpt.weeklyQuota {
                            miniQuotaChip(
                                label: "Tuần",
                                remainingPct: q7.remainingPercent,
                                color: PulseTheme.teal
                            )
                        }
                    }

                    Spacer(minLength: 2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .telemetryCard(accent: PulseTheme.cobalt, cornerRadius: 10, padding: 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bấm để mở chi tiết Hạn mức AI (Antigravity & ChatGPT)")
        }
    }

    private func miniQuotaChip(label: String, remainingPct: Double, color: Color) -> some View {
        let barColor: Color = remainingPct <= 15 ? PulseTheme.crimson : (remainingPct <= 35 ? PulseTheme.amber : color)
        return HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(3, 28 * CGFloat(max(0, min(1, remainingPct / 100.0)))))
            }
            .frame(width: 28, height: 4.5)
            Text("\(Int(remainingPct.rounded()))%")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(barColor)
        }
    }

    // MARK: - Precision Telemetry Grid (CPU + Sparkline / RAM + Segmented Bar / SSD + Ring)
    private var metricsGrid: some View {
        HStack(spacing: 9) {
            if let snap = vm.snapshot {
                let cpuColor: Color = snap.cpu.totalBusyPercent >= 75 ? PulseTheme.crimson : (snap.cpu.totalBusyPercent >= 45 ? PulseTheme.amber : PulseTheme.cyan)
                let ramColor: Color = snap.memory.compressedGB >= 5.0 ? PulseTheme.crimson : (snap.memory.compressedGB >= 3.5 ? PulseTheme.amber : PulseTheme.cobalt)
                let ssdColor: Color = snap.disk.availableGB < 20 ? PulseTheme.crimson : (snap.disk.availableGB < 32 ? PulseTheme.amber : PulseTheme.emerald)

                // CPU Telemetry Tile
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(cpuColor)
                            Text("CPU")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "L %.1f", snap.cpu.load1m))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text(String(format: "%.0f%%", snap.cpu.totalBusyPercent))
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(cpuColor)
                        .contentTransition(.numericText())

                    LiveSparklineView(samples: vm.cpuHistory, color: cpuColor, maxValue: 100, height: 24)

                    Text(String(format: "Usr %.0f%% • Sys %.0f%%", snap.cpu.userPercent, snap.cpu.systemPercent))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .telemetryCard(accent: cpuColor, cornerRadius: 11, padding: 10)

                // RAM Telemetry Tile (Activity Monitor Accurate)
                Button {
                    vm.cleanerFocus = .ram
                    vm.selectedTab = .cleaner
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "memorychip")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(ramColor)
                                Text("RAM TRỐNG")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(0.5)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", snap.memory.usedPercent))
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Text(String(format: "%.1f GB", snap.memory.availableGB))
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(ramColor)
                            .contentTransition(.numericText())

                        VStack(spacing: 5) {
                            LiveSparklineView(samples: vm.ramHistory, color: ramColor, maxValue: 100, height: 15)
                            SegmentedMemoryBar(memory: snap.memory, height: 4.5)
                        }

                        Text(String(format: "Nén %.1fG • Swp %.1fG", snap.memory.compressedGB, snap.memory.swapUsedGB))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .telemetryCard(accent: ramColor, cornerRadius: 11, padding: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("App: \(String(format: "%.1fG", snap.memory.appMemoryGB)) • Wired: \(String(format: "%.1fG", snap.memory.wiredGB)) • Nén: \(String(format: "%.1fG", snap.memory.compressedGB)) • Cache: \(String(format: "%.1fG", snap.memory.cachedGB))\nBấm để mở mục Giải phóng RAM")

                // SSD Telemetry Tile
                Button {
                    vm.cleanerFocus = .all
                    vm.selectedTab = .cleaner
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(ssdColor)
                                Text("SSD TRỐNG")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(0.5)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.1f", snap.disk.availableGB))
                                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(ssdColor)
                                Text("GB khả dụng")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            QuotaRingView(
                                remainingPercent: max(0, 100.0 - snap.disk.usedPercent),
                                color: ssdColor,
                                size: 38,
                                lineWidth: 3.8
                            )
                        }

                        Text(vm.totalSafeCacheBytes > 10 * 1_048_576
                             ? "Dọn được \(Formatters.bytes(vm.totalSafeCacheBytes))"
                             : String(format: "Tổng %.0f GB APFS", snap.disk.totalGB))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(vm.totalSafeCacheBytes > 100 * 1_048_576 ? PulseTheme.emerald : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .telemetryCard(accent: ssdColor, cornerRadius: 11, padding: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bấm để mở mục Dọn Cache & SSD")
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Đang khởi tạo cảm biến hệ thống...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .telemetryCard(cornerRadius: 11, padding: 16)
            }
        }
    }

    // MARK: - Diagnostics Alert Deck
    @ViewBuilder
    private var findingsSection: some View {
        if let report = vm.healthReport {
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrow(
                    icon: report.findings.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                    title: report.findings.isEmpty ? "Chẩn đoán hệ thống" : "Cảnh báo & Tối ưu nhanh",
                    color: report.findings.isEmpty ? PulseTheme.emerald : PulseTheme.amber,
                    trailingText: report.findings.isEmpty ? "OPTIMAL" : "\(report.findings.count) MỤC"
                )

                if report.findings.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(PulseTheme.emerald)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Hệ thống đang vận hành tối ưu")
                                .font(.system(size: 12, weight: .semibold))
                            Text("CPU, RAM nén, nhiệt độ và ổ cứng SSD đều thông thoáng — không phát hiện điểm nghẽn.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .telemetryCard(accent: PulseTheme.emerald, cornerRadius: 10, padding: 10)
                } else {
                    ForEach(report.findings) { item in
                        let isCrit = item.severity == .critical
                        let accentColor: Color = isCrit ? PulseTheme.crimson : PulseTheme.amber

                        HStack(alignment: .top, spacing: 9) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentColor)
                                .frame(width: 3)
                                .padding(.vertical, 2)

                            Image(systemName: isCrit ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(accentColor)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !item.impactNote.isEmpty {
                                    Text(item.impactNote)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(accentColor.opacity(0.92))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer(minLength: 4)

                            if item.recommendedAction != .none {
                                Button(item.actionLabel ?? "Xử lý") {
                                    vm.performRecommendedAction(item.recommendedAction, targetID: item.targetID)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(accentColor)
                                .controlSize(.small)
                            }
                        }
                        .telemetryCard(accent: accentColor, cornerRadius: 10, padding: 10)
                    }
                }
            }
        }
    }

    // MARK: - Process Monitor Table
    private var topProcessesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionEyebrow(
                    icon: "list.bullet.rectangle.portrait",
                    title: "Giám sát Tiến trình",
                    color: PulseTheme.cyan,
                    trailingText: "\(vm.filteredProcessGroups.count) nhóm"
                )
                Button(vm.isScanningTabs ? "Đang quét..." : "Soi tab") {
                    vm.scanBrowserTabs()
                }
                .controlSize(.mini)
                .disabled(vm.isScanningTabs)
                .help("Quét toàn bộ tab đang mở trên Chrome, Brave, Edge, Arc, Safari")
            }

            // Search bar + Sort picker
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    TextField("Tìm app, tiến trình hoặc PID...", text: $vm.processSearchQuery)
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
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
                )

                // Sort order pills
                HStack(spacing: 2) {
                    ForEach(ProcessSortOrder.allCases) { order in
                        let active = vm.processSortOrder == order
                        Button {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                vm.processSortOrder = order
                            }
                        } label: {
                            Text(order.rawValue)
                                .font(.system(size: 9.5, weight: active ? .bold : .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(active ? PulseTheme.cyan.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(active ? PulseTheme.cyan : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            }

            // Category filter chips
            HStack(spacing: 5) {
                ForEach(ProcessFilterCategory.allCases) { cat in
                    let active = vm.processCategoryFilter == cat
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            vm.processCategoryFilter = cat
                        }
                    } label: {
                        Text(cat.rawValue)
                            .font(.system(size: 10, weight: active ? .semibold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(active ? PulseTheme.cobalt : Color.primary.opacity(0.06), in: Capsule())
                            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Rê vào ⓘ để xem tác động")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            let allMatching = vm.filteredProcessGroups
            let displayList = vm.showAllProcesses ? allMatching : Array(allMatching.prefix(12))
            if displayList.isEmpty {
                Text("Không tìm thấy tiến trình nào khớp bộ lọc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .telemetryCard(cornerRadius: 9, padding: 14)
            } else {
                VStack(spacing: 5) {
                    ForEach(displayList) { group in
                        ProcessRowView(group: group, vm: vm, highlightRAM: false)
                    }
                }
                if allMatching.count > 12 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            vm.showAllProcesses.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(vm.showAllProcesses ? "Thu gọn danh sách" : "Xem tất cả \(allMatching.count) tiến trình")
                                .font(.system(size: 10.5, weight: .semibold))
                            Image(systemName: vm.showAllProcesses ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
