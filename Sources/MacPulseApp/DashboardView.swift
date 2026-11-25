import SwiftUI
import MacPulseCore

struct DashboardView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                aiQuotaUplinkStrip
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

    // MARK: - AI Telemetry Uplink Strip
    @ViewBuilder
    private var aiQuotaUplinkStrip: some View {
        if let ai = vm.aiSnapshot, (ai.antigravity?.isDetected == true || ai.chatGPT?.isDetected == true) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    vm.selectedTab = .aiPulse
                }
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        LivePulseDot(
                            color: (ai.antigravity?.sourceState == .live || ai.chatGPT?.sourceState == .live) ? HudTheme.emerald : HudTheme.amber,
                            isLive: ai.antigravity?.sourceState == .live || ai.chatGPT?.sourceState == .live
                        )
                        Text("AI UPLINK")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(HudTheme.cyan)
                    }

                    Rectangle()
                        .fill(HudTheme.cyan.opacity(0.28))
                        .frame(width: 1, height: 14)

                    if let agy = ai.antigravity, agy.isDetected, let q5 = agy.fiveHourQuota {
                        miniQuotaChip(label: "AGY 5H", remainingPct: q5.remainingPercent, color: HudTheme.cobalt)
                    }

                    if let gpt = ai.chatGPT, gpt.isDetected {
                        if let q5 = gpt.fiveHourQuota {
                            miniQuotaChip(label: "GPT 5H", remainingPct: q5.remainingPercent, color: HudTheme.emerald)
                        }
                        if let q7 = gpt.weeklyQuota {
                            miniQuotaChip(label: "7D", remainingPct: q7.remainingPercent, color: HudTheme.teal)
                        }
                    }

                    Spacer(minLength: 2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(HudTheme.cyan)
                }
                .hudCard(accent: HudTheme.cyan, chamfer: 7, padding: 8, showBrackets: false)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bấm để mở AI Quota Command Center")
        }
    }

    private func miniQuotaChip(label: String, remainingPct: Double, color: Color) -> some View {
        let barColor: Color = remainingPct <= 15 ? HudTheme.crimson : (remainingPct <= 35 ? HudTheme.amber : color)
        return HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(HudTheme.textSecondary)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(HudTheme.insetBg)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(barColor.opacity(0.25), lineWidth: 0.5))
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: max(3, 28 * CGFloat(max(0, min(1, remainingPct / 100.0)))))
                    .shadow(color: barColor.opacity(0.75), radius: 2.5)
            }
            .frame(width: 28, height: 5)
            Text("\(Int(remainingPct.rounded()))%")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(barColor)
        }
    }

    // MARK: - 3-Channel Holographic Telemetry Grid
    private var metricsGrid: some View {
        HStack(spacing: 9) {
            if let snap = vm.snapshot {
                let cpuColor: Color = snap.cpu.totalBusyPercent >= 75 ? HudTheme.crimson : (snap.cpu.totalBusyPercent >= 45 ? HudTheme.amber : HudTheme.cyan)
                let ramColor: Color = snap.memory.compressedGB >= 5.0 ? HudTheme.crimson : (snap.memory.compressedGB >= 3.5 ? HudTheme.amber : HudTheme.cobalt)
                let ssdColor: Color = snap.disk.availableGB < 20 ? HudTheme.crimson : (snap.disk.availableGB < 32 ? HudTheme.amber : HudTheme.emerald)

                // 01 :: CPU CORE
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(cpuColor)
                            Text("CPU CORE")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(HudTheme.textSecondary)
                        }
                        Spacer()
                        Text(String(format: "L %.1f", snap.cpu.load1m))
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(HudTheme.textMuted)
                    }

                    Text(String(format: "%.0f%%", snap.cpu.totalBusyPercent))
                        .font(.system(size: 21, weight: .black, design: .monospaced))
                        .foregroundStyle(cpuColor)
                        .shadow(color: cpuColor.opacity(0.45), radius: 4)
                        .contentTransition(.numericText())

                    LiveSparklineView(samples: vm.cpuHistory, color: cpuColor, maxValue: 100, height: 26)

                    Text(String(format: "USR %.0f%% • SYS %.0f%%", snap.cpu.userPercent, snap.cpu.systemPercent))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudCard(accent: cpuColor, chamfer: 10, padding: 10, showBrackets: true)

                // 02 :: MEMORY MATRIX
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
                                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundStyle(HudTheme.textSecondary)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", snap.memory.usedPercent))
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(ramColor)
                        }

                        Text(String(format: "%.1f GB", snap.memory.availableGB))
                            .font(.system(size: 21, weight: .black, design: .monospaced))
                            .foregroundStyle(ramColor)
                            .shadow(color: ramColor.opacity(0.45), radius: 4)
                            .contentTransition(.numericText())

                        VStack(spacing: 5) {
                            LiveSparklineView(samples: vm.ramHistory, color: ramColor, maxValue: 100, height: 15)
                            SegmentedMemoryBar(memory: snap.memory, height: 5.5)
                        }

                        Text(String(format: "NÉN %.1fG • SWP %.1fG", snap.memory.compressedGB, snap.memory.swapUsedGB))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HudTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hudCard(accent: ramColor, chamfer: 10, padding: 10, showBrackets: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("App: \(String(format: "%.1fG", snap.memory.appMemoryGB)) • Wired: \(String(format: "%.1fG", snap.memory.wiredGB)) • Nén: \(String(format: "%.1fG", snap.memory.compressedGB)) • Cache: \(String(format: "%.1fG", snap.memory.cachedGB))\nBấm để mở mục Giải phóng RAM")

                // 03 :: NVME STORAGE
                Button {
                    vm.cleanerFocus = .all
                    vm.selectedTab = .cleaner
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ssdColor)
                            Text("SSD NVME")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .tracking(0.5)
                                .foregroundStyle(HudTheme.textSecondary)
                            Spacer()
                        }

                        HStack(alignment: .center, spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(format: "%.1f", snap.disk.availableGB))
                                    .font(.system(size: 21, weight: .black, design: .monospaced))
                                    .foregroundStyle(ssdColor)
                                    .shadow(color: ssdColor.opacity(0.45), radius: 4)
                                Text("GB KHẢ DỤNG")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(HudTheme.textMuted)
                            }
                            Spacer(minLength: 0)
                            QuotaRingView(
                                remainingPercent: max(0, 100.0 - snap.disk.usedPercent),
                                color: ssdColor,
                                size: 42,
                                lineWidth: 3.8
                            )
                        }

                        Text(vm.totalSafeCacheBytes > 10 * 1_048_576
                             ? "DỌN ĐƯỢC \(Formatters.bytes(vm.totalSafeCacheBytes).uppercased())"
                             : String(format: "TỔNG %.0f GB APFS", snap.disk.totalGB))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(vm.totalSafeCacheBytes > 100 * 1_048_576 ? HudTheme.emerald : HudTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hudCard(accent: ssdColor, chamfer: 10, padding: 10, showBrackets: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bấm để mở mục Dọn Cache & SSD")
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("INITIALIZING TELEMETRY SENSORS...")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HudTheme.cyan)
                }
                .frame(maxWidth: .infinity)
                .hudCard(accent: HudTheme.cyan, chamfer: 10, padding: 16)
            }
        }
    }

    // MARK: - Tactical Diagnostic Alert Deck (Compact Sci-Fi Strips)
    @ViewBuilder
    private var findingsSection: some View {
        if let report = vm.healthReport {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow(
                    icon: report.findings.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                    title: report.findings.isEmpty ? "Trạng thái hệ thống" : "Cảnh báo & Tối ưu nhanh",
                    color: report.findings.isEmpty ? HudTheme.emerald : HudTheme.amber,
                    trailingText: report.findings.isEmpty ? "OPTIMAL" : "\(report.findings.count) ACTIVE"
                )

                if report.findings.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(HudTheme.emerald)
                            .shadow(color: HudTheme.emerald.opacity(0.6), radius: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Toàn bộ hệ thống đang vận hành tối ưu")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(HudTheme.textPrimary)
                            Text("CPU, RAM nén, nhiệt độ và ổ cứng SSD đều thông thoáng — không có điểm nghẽn.")
                                .font(.system(size: 10))
                                .foregroundStyle(HudTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .hudCard(accent: HudTheme.emerald, chamfer: 8, padding: 9)
                } else {
                    ForEach(report.findings) { item in
                        let isCrit = item.severity == .critical
                        let accentColor: Color = isCrit ? HudTheme.crimson : HudTheme.amber

                        HStack(alignment: .center, spacing: 9) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentColor)
                                .frame(width: 3, height: 34)
                                .shadow(color: accentColor.opacity(0.8), radius: 3)

                            Image(systemName: isCrit ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 13.5))
                                .foregroundStyle(accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(HudTheme.textPrimary)
                                    .lineLimit(1)

                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(HudTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 4)

                            if item.recommendedAction != .none {
                                HudButton(
                                    title: item.actionLabel ?? "Xử lý",
                                    color: accentColor,
                                    filled: true,
                                    compact: true
                                ) {
                                    vm.performRecommendedAction(item.recommendedAction, targetID: item.targetID)
                                }
                            }
                        }
                        .hudCard(accent: accentColor, chamfer: 8, padding: 8.5, showBrackets: false)
                    }
                }
            }
        }
    }

    // MARK: - Process Radar Table
    private var topProcessesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                SectionEyebrow(
                    icon: "scope",
                    title: "Radar Tiến trình",
                    color: HudTheme.cyan,
                    trailingText: "\(vm.filteredProcessGroups.count)"
                )
                HudButton(
                    title: vm.isScanningTabs ? "Đang quét..." : "Soi tab",
                    icon: "macwindow.on.rectangle",
                    color: HudTheme.cyan,
                    filled: false,
                    compact: true,
                    disabled: vm.isScanningTabs
                ) {
                    vm.scanBrowserTabs()
                }
            }

            // Search bar + Sort pills
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(HudTheme.cyan)
                    TextField("Tìm app, tiến trình hoặc PID...", text: $vm.processSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(HudTheme.textPrimary)
                    if !vm.processSearchQuery.isEmpty {
                        Button {
                            vm.processSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(HudTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5.5)
                .background(HudTheme.insetBg, in: ChamferedRect(cut: 5, cornerRadius: 3))
                .overlay(ChamferedRect(cut: 5, cornerRadius: 3).strokeBorder(HudTheme.cyan.opacity(0.28), lineWidth: 0.8))

                HStack(spacing: 2) {
                    ForEach(ProcessSortOrder.allCases) { order in
                        let active = vm.processSortOrder == order
                        Button {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                vm.processSortOrder = order
                            }
                        } label: {
                            Text(order.rawValue)
                                .font(.system(size: 9.5, weight: active ? .bold : .medium, design: .monospaced))
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 4.5)
                                .background(active ? HudTheme.cyan.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(active ? HudTheme.cyan : HudTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.textMuted.opacity(0.25), lineWidth: 0.7))
            }

            // Category filter pills
            HStack(spacing: 5) {
                ForEach(ProcessFilterCategory.allCases) { cat in
                    let active = vm.processCategoryFilter == cat
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            vm.processCategoryFilter = cat
                        }
                    } label: {
                        Text(cat.rawValue)
                            .font(.system(size: 10, weight: active ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(active ? HudTheme.cobalt.opacity(0.32) : HudTheme.cardBg, in: Capsule())
                            .overlay(Capsule().strokeBorder(active ? HudTheme.cobalt.opacity(0.85) : HudTheme.textMuted.opacity(0.25), lineWidth: 0.75))
                            .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Rê ⓘ xem chi tiết")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(HudTheme.textMuted)
            }

            let allMatching = vm.filteredProcessGroups
            let displayList = vm.showAllProcesses ? allMatching : Array(allMatching.prefix(12))
            if displayList.isEmpty {
                Text("Không tìm thấy tiến trình nào khớp bộ lọc.")
                    .font(.caption)
                    .foregroundStyle(HudTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .hudCard(accent: HudTheme.textMuted, chamfer: 8, padding: 14)
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
                        HStack(spacing: 5) {
                            Text(vm.showAllProcesses ? "THU GỌN DANH SÁCH" : "XEM TẤT CẢ \(allMatching.count) TIẾN TRÌNH")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Image(systemName: vm.showAllProcesses ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(HudTheme.cardBg, in: ChamferedRect(cut: 5, cornerRadius: 3))
                        .overlay(ChamferedRect(cut: 5, cornerRadius: 3).strokeBorder(HudTheme.cyan.opacity(0.30), lineWidth: 0.8))
                        .foregroundStyle(HudTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
