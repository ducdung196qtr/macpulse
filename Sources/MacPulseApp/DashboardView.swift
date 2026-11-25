import SwiftUI
import MacPulseCore

private enum DashboardSubTab: String, CaseIterable, Identifiable {
    case alerts = "Cảnh báo"
    case processes = "Tiến trình"
    var id: String { rawValue }
}

struct DashboardView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedSubTab: DashboardSubTab = .alerts
    @State private var hasInitializedSubTab: Bool = false

    private var alertCount: Int {
        vm.healthReport?.findings.count ?? 0
    }

    private var hasCriticalAlert: Bool {
        vm.healthReport?.findings.contains(where: { $0.severity == .critical }) == true
    }

    private var hasChromeIssue: Bool {
        vm.isReplaydStuck || vm.orphanAutomationGroup != nil || !vm.stuckChromeRenderers.isEmpty || vm.chromeGPUTotalCPU >= 12.0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed Top Telemetry & Command Deck
            VStack(spacing: 9) {
                metricsGrid
                quickCommandBar
                subTabSwitcher
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Scrollable Workspace
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if let pending = vm.pendingTerminationGroup {
                        InlineConfirmTerminationCard(group: pending, vm: vm)
                    }

                    if vm.showTabInspector {
                        BrowserTabsInspectorCard(vm: vm)
                    }

                    switch selectedSubTab {
                    case .alerts:
                        alertsWorkspace
                    case .processes:
                        processesWorkspace
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            if !hasInitializedSubTab {
                selectedSubTab = alertCount > 0 ? .alerts : .processes
                hasInitializedSubTab = true
            }
        }
    }

    // MARK: - 1. Clean 3-Card Telemetry Strip
    private var metricsGrid: some View {
        HStack(spacing: 8) {
            if let snap = vm.snapshot {
                let cpuColor: Color = snap.cpu.totalBusyPercent >= 75 ? HudTheme.crimson : (snap.cpu.totalBusyPercent >= 45 ? HudTheme.amber : HudTheme.cyan)
                let ramColor: Color = snap.memory.compressedGB >= 5.0 ? HudTheme.crimson : (snap.memory.compressedGB >= 3.5 ? HudTheme.amber : HudTheme.cobalt)
                let ssdColor: Color = snap.disk.availableGB < 20 ? HudTheme.crimson : (snap.disk.availableGB < 32 ? HudTheme.amber : HudTheme.emerald)

                // CPU Card
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("CPU")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.textSecondary)
                        Spacer()
                        Text(String(format: "Load %.1f", snap.cpu.load1m))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HudTheme.textMuted)
                    }

                    Text(String(format: "%.0f%%", snap.cpu.totalBusyPercent))
                        .font(.system(size: 21, weight: .black, design: .monospaced))
                        .foregroundStyle(cpuColor)

                    LiveSparklineView(samples: vm.cpuHistory, color: cpuColor, maxValue: 100, height: 22)

                    Text(String(format: "User %.0f%% • Sys %.0f%%", snap.cpu.userPercent, snap.cpu.systemPercent))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HudTheme.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudCard(accent: snap.cpu.totalBusyPercent >= 45 ? cpuColor : HudTheme.borderSubtle, chamfer: 9, padding: 9, showBrackets: snap.cpu.totalBusyPercent >= 75)

                // RAM Card -> Jumps to Cleaner RAM
                Button {
                    vm.cleanerFocus = .ram
                    vm.selectedTab = .cleaner
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("RAM TRỐNG")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.0f%%", snap.memory.usedPercent))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(ramColor)
                        }

                        Text(String(format: "%.1f GB", snap.memory.availableGB))
                            .font(.system(size: 21, weight: .black, design: .monospaced))
                            .foregroundStyle(ramColor)

                        VStack(spacing: 4) {
                            LiveSparklineView(samples: vm.ramHistory, color: ramColor, maxValue: 100, height: 13)
                            SegmentedMemoryBar(memory: snap.memory, height: 5)
                        }

                        Text(String(format: "Nén %.1fG • Swap %.1fG", snap.memory.compressedGB, snap.memory.swapUsedGB))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(HudTheme.textMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hudCard(accent: snap.memory.compressedGB >= 3.5 ? ramColor : HudTheme.borderSubtle, chamfer: 9, padding: 9, showBrackets: snap.memory.compressedGB >= 5.0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bấm để mở mục Giải phóng RAM")

                // SSD Card -> Jumps to Cleaner SSD
                Button {
                    vm.cleanerFocus = .ssd
                    vm.selectedTab = .cleaner
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("SSD TRỐNG")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.0f%%", max(0, 100.0 - snap.disk.usedPercent)))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(ssdColor)
                        }

                        Text(String(format: "%.1f GB", snap.disk.availableGB))
                            .font(.system(size: 21, weight: .black, design: .monospaced))
                            .foregroundStyle(ssdColor)

                        GeometryReader { geo in
                            let usedRatio = max(0.05, min(1.0, snap.disk.usedPercent / 100.0))
                            ZStack(alignment: .leading) {
                                Capsule().fill(HudTheme.insetBg)
                                Capsule()
                                    .fill(ssdColor)
                                    .frame(width: geo.size.width * CGFloat(usedRatio))
                            }
                        }
                        .frame(height: 5)
                        .padding(.vertical, 8.5)

                        Text(vm.totalSafeCacheBytes > 10 * 1_048_576
                             ? "Dọn được \(Formatters.bytes(vm.totalSafeCacheBytes))"
                             : String(format: "Tổng %.0f GB", snap.disk.totalGB))
                            .font(.system(size: 9, weight: vm.totalSafeCacheBytes > 100 * 1_048_576 ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(vm.totalSafeCacheBytes > 100 * 1_048_576 ? HudTheme.emerald : HudTheme.textMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hudCard(accent: snap.disk.availableGB < 32 ? ssdColor : HudTheme.borderSubtle, chamfer: 9, padding: 9, showBrackets: snap.disk.availableGB < 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bấm để mở mục Dọn SSD")
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Đang đọc cảm biến hệ thống...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HudTheme.cyan)
                }
                .frame(maxWidth: .infinity)
                .cleanCard(padding: 14)
            }
        }
    }

    // MARK: - 2. One-Line Quick Command Bar (AI Uplink + Fast Actions)
    private var quickCommandBar: some View {
        HStack(spacing: 7) {
            // OpenCode / GPT compact status chip
            Button {
                vm.selectedTab = .aiPulse
            } label: {
                let ocCount = vm.openCodeRunningSessions.count
                let ocUnread = vm.openCodeUnreadCompletions
                let chipColor: Color = ocCount > 0 ? HudTheme.cyan : (ocUnread > 0 ? HudTheme.emerald : HudTheme.textSecondary)
                HStack(spacing: 5.5) {
                    LivePulseDot(
                        color: ocCount > 0 ? HudTheme.cyan : (vm.openCodeConfig.isEnabled ? HudTheme.emerald : HudTheme.textMuted),
                        isLive: ocCount > 0
                    )
                    Text(ocCount > 0 ? "OC: \(ocCount) đang chạy" : (ocUnread > 0 ? "OC: \(ocUnread) xong" : "OpenCode"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ocCount > 0 || ocUnread > 0 ? chipColor : HudTheme.textPrimary)
                        .lineLimit(1)

                    if let q5 = vm.aiSnapshot?.chatGPT?.fiveHourQuota {
                        Text("•")
                            .foregroundStyle(HudTheme.textMuted)
                        Text("GPT \(Int(q5.remainingPercent.rounded()))%")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(q5.remainingPercent <= 20 ? HudTheme.amber : HudTheme.emerald)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .background(HudTheme.cardBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder((ocCount > 0 ? HudTheme.cyan : HudTheme.borderSubtle).opacity(0.45), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help("Mở OpenCode Task Watcher & ChatGPT Quota")

            Spacer(minLength: 2)

            // Direct Chrome Fix button when Chrome/replayd has issue (or quick jump)
            let chromeColor: Color = vm.isReplaydStuck ? HudTheme.crimson : (hasChromeIssue ? HudTheme.amber : HudTheme.textSecondary)
            HudButton(
                title: vm.isReplaydStuck ? "Fix replayd" : (hasChromeIssue ? "Sửa Chrome" : "Chrome"),
                icon: hasChromeIssue ? "exclamationmark.shield.fill" : "lifepreserver",
                color: chromeColor,
                filled: hasChromeIssue,
                compact: true
            ) {
                vm.cleanerFocus = .chrome
                vm.selectedTab = .cleaner
            }

            // 1-click Turbo Optimize
            HudButton(
                title: vm.isAutoOptimizing ? "Đang tối ưu..." : "Tối ưu nhanh",
                icon: "bolt.fill",
                color: HudTheme.emerald,
                filled: true,
                compact: true,
                disabled: vm.isAutoOptimizing || vm.isCleaning || vm.isRescuingChrome
            ) {
                vm.runAutoOptimizeNow()
            }
        }
    }

    // MARK: - 3. Sub-Tab Switcher (Alerts vs Processes)
    private var subTabSwitcher: some View {
        let alertDot: Color? = alertCount == 0 ? nil : (hasCriticalAlert ? HudTheme.crimson : HudTheme.amber)
        let items: [HudSegmentItem<DashboardSubTab>] = [
            HudSegmentItem(
                id: .alerts,
                title: "Cảnh báo & Đề xuất",
                icon: alertCount == 0 ? "checkmark.shield" : "exclamationmark.triangle.fill",
                badge: alertCount > 0 ? "\(alertCount)" : "0",
                dotColor: alertDot
            ),
            HudSegmentItem(
                id: .processes,
                title: "Ứng dụng & Tiến trình",
                icon: "list.bullet.rectangle",
                badge: "\(vm.filteredProcessGroups.count)"
            )
        ]
        return HudSegmentedBar(items: items, selection: $selectedSubTab, accent: HudTheme.cyan)
    }

    // MARK: - Workspace A: Clean Alerts Deck
    @ViewBuilder
    private var alertsWorkspace: some View {
        if let report = vm.healthReport {
            if report.findings.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(HudTheme.emerald)
                    Text("Hệ thống đang vận hành mượt mà")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text("CPU, RAM nén, nhiệt độ và ổ cứng SSD đều ở trạng thái tối ưu — không phát hiện điểm nghẽn.")
                        .font(.system(size: 11))
                        .foregroundStyle(HudTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    HudButton(title: "Xem ứng dụng đang chạy", icon: "list.bullet", color: HudTheme.cyan, filled: false, compact: true) {
                        selectedSubTab = .processes
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .cleanCard(accent: HudTheme.emerald, cornerRadius: 10, padding: 20)
            } else {
                VStack(spacing: 7) {
                    ForEach(report.findings) { item in
                        let isCrit = item.severity == .critical
                        let accentColor: Color = isCrit ? HudTheme.crimson : HudTheme.amber

                        HStack(alignment: .center, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentColor)
                                .frame(width: 3, height: 34)

                            VStack(alignment: .leading, spacing: 2.5) {
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(HudTheme.textPrimary)
                                    .lineLimit(1)

                                Text(item.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(HudTheme.textSecondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 6)

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
                        .cleanCard(accent: accentColor, cornerRadius: 8, padding: 10)
                    }
                }
            }
        }
    }

    // MARK: - Workspace B: Clean Tabular Process Radar
    private var processesWorkspace: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Compact Search + Sort + Tab Inspector
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5))
                        .foregroundStyle(HudTheme.textMuted)
                    TextField("Tìm ứng dụng hoặc PID...", text: $vm.processSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(HudTheme.textPrimary)
                    if !vm.processSearchQuery.isEmpty {
                        Button {
                            vm.processSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(HudTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5.5)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(HudTheme.borderSubtle.opacity(0.42), lineWidth: 0.75))

                HStack(spacing: 2) {
                    ForEach(ProcessSortOrder.allCases) { order in
                        let active = vm.processSortOrder == order
                        Button {
                            vm.processSortOrder = order
                        } label: {
                            Text(order.rawValue)
                                .font(.system(size: 9.5, weight: active ? .bold : .medium, design: .monospaced))
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 4.5)
                                .background(active ? HudTheme.cyan.opacity(0.20) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(active ? HudTheme.cyan : HudTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.borderSubtle.opacity(0.35), lineWidth: 0.7))

                HudButton(
                    title: vm.isScanningTabs ? "Đang quét" : "Soi tab",
                    icon: "macwindow",
                    color: HudTheme.cyan,
                    filled: false,
                    compact: true,
                    disabled: vm.isScanningTabs
                ) {
                    vm.scanBrowserTabs()
                }
            }

            // Category Pills + Legend
            HStack(spacing: 5) {
                ForEach(ProcessFilterCategory.allCases) { cat in
                    let active = vm.processCategoryFilter == cat
                    Button {
                        vm.processCategoryFilter = cat
                    } label: {
                        Text(cat.rawValue)
                            .font(.system(size: 10, weight: active ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(active ? HudTheme.cobalt.opacity(0.28) : HudTheme.cardBg, in: Capsule())
                            .overlay(Capsule().strokeBorder(active ? HudTheme.cobalt.opacity(0.75) : HudTheme.borderSubtle.opacity(0.35), lineWidth: 0.7))
                            .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Bấm tên để xem chi tiết")
                    .font(.system(size: 9))
                    .foregroundStyle(HudTheme.textMuted)
            }

            // Crisp Table Column Header
            HStack(spacing: 8) {
                Text("ỨNG DỤNG / DỊCH VỤ")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textMuted)
                Spacer()
                Text("CPU")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textMuted)
                    .frame(width: 42, alignment: .trailing)
                Text("RAM")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textMuted)
                    .frame(width: 64, alignment: .trailing)
                Text("XỬ LÝ")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textMuted)
                    .frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .padding(.top, 2)

            let allMatching = vm.filteredProcessGroups
            let displayList = vm.showAllProcesses ? allMatching : Array(allMatching.prefix(10))
            if displayList.isEmpty {
                Text("Không tìm thấy tiến trình nào khớp bộ lọc.")
                    .font(.caption)
                    .foregroundStyle(HudTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .cleanCard(padding: 16)
            } else {
                LazyVStack(spacing: 4.5) {
                    ForEach(displayList) { group in
                        ProcessRowView(group: group, vm: vm, highlightRAM: false)
                    }
                }
                if allMatching.count > 10 {
                    Button {
                        vm.showAllProcesses.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Text(vm.showAllProcesses ? "Thu gọn danh sách" : "Xem tất cả \(allMatching.count) tiến trình")
                                .font(.system(size: 10.5, weight: .semibold))
                            Image(systemName: vm.showAllProcesses ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6.5)
                        .background(HudTheme.cardBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(HudTheme.borderSubtle.opacity(0.45), lineWidth: 0.75))
                        .foregroundStyle(HudTheme.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
