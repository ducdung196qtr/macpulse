import SwiftUI
import MacPulseCore

struct CleanerView: View {
    @ObservedObject var vm: AppViewModel
    @State private var collapsedGroups: Set<String> = ["storage"]

    private var hasChromeAlert: Bool {
        vm.isReplaydStuck || vm.orphanAutomationGroup != nil || !vm.stuckChromeRenderers.isEmpty || vm.chromeGPUTotalCPU >= 8.0
    }

    private static let historyDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm dd/MM"
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Unmistakable 4-Tile Visual Tool Hub (SSD · RAM · Chrome · Autopilot)
            cleanerToolHubGrid
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let pending = vm.pendingTerminationGroup {
                        InlineConfirmTerminationCard(group: pending, vm: vm)
                    }

                    if vm.showTabInspector {
                        BrowserTabsInspectorCard(vm: vm)
                    }

                    if let msg = vm.cleanupOutcomeMessage {
                        outcomeBanner(msg)
                    }

                    switch vm.cleanerFocus {
                    case .ssd:
                        ssdWorkspace
                    case .ram:
                        ramWorkspace
                    case .chrome:
                        chromeWorkspace
                    case .autopilot:
                        autopilotWorkspace
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            if vm.cleanerFocus == .ram || vm.cleanerFocus == .autopilot {
                vm.refreshTrackedGUIApps()
            }
        }
        .onChange(of: vm.cleanerFocus) { _, newSection in
            if newSection == .ram || newSection == .autopilot {
                vm.refreshTrackedGUIApps()
            }
        }
    }

    // MARK: - Unmistakable 4-Tile Visual Tool Hub
    private var cleanerToolHubGrid: some View {
        let mem = vm.snapshot?.memory
        let ramAccent: Color = {
            guard let m = mem else { return HudTheme.cyan }
            if m.compressedGB >= 5.0 { return HudTheme.crimson }
            if m.compressedGB >= 3.5 { return HudTheme.amber }
            return HudTheme.cyan
        }()
        let ramSubtitle: String = {
            guard let m = mem else { return "Đang đo..." }
            if m.compressedGB >= 4.0 {
                return String(format: "Nén %.1fG", m.compressedGB)
            }
            return String(format: "%.1fG trống", m.availableGB)
        }()

        let chromeAccent: Color = vm.isReplaydStuck ? HudTheme.crimson : (hasChromeAlert ? HudTheme.amber : HudTheme.cobalt)
        let chromeSubtitle: String = {
            if vm.isReplaydStuck, let r = vm.replaydProcessGroup {
                return "replayd \(Int(r.totalCPUPercent.rounded()))%"
            }
            if let auto = vm.orphanAutomationGroup {
                return "\(auto.processCount) bot ngầm"
            }
            if !vm.stuckChromeRenderers.isEmpty {
                return "\(vm.stuckChromeRenderers.count) tab đơ"
            }
            if vm.chromeGPUTotalCPU >= 8.0 {
                return "GPU \(Int(vm.chromeGPUTotalCPU.rounded()))%"
            }
            return "Ổn định"
        }()

        let ssdSubtitle = vm.totalSafeCacheBytes >= 10 * 1_048_576
            ? "\(Formatters.bytes(vm.totalSafeCacheBytes)) rác"
            : "Đã sạch"

        let autoOn = vm.autoOptimizeConfig.isEnabled
        let autoSubtitle = autoOn ? "BẬT • \(vm.autoOptimizeConfig.intervalHours)h" : "Đang tắt"

        return HStack(spacing: 7) {
            toolTile(
                section: .ssd,
                title: "Dọn SSD",
                subtitle: ssdSubtitle,
                icon: "internaldrive.fill",
                accent: HudTheme.emerald,
                hasAlertDot: false
            )
            toolTile(
                section: .ram,
                title: "Giải phóng RAM",
                subtitle: ramSubtitle,
                icon: "memorychip.fill",
                accent: ramAccent,
                hasAlertDot: (mem?.compressedGB ?? 0) >= 5.0
            )
            toolTile(
                section: .chrome,
                title: "Sửa Chrome",
                subtitle: chromeSubtitle,
                icon: "lifepreserver.fill",
                accent: chromeAccent,
                hasAlertDot: hasChromeAlert
            )
            toolTile(
                section: .autopilot,
                title: "Tự động",
                subtitle: autoSubtitle,
                icon: "bolt.shield.fill",
                accent: autoOn ? HudTheme.emerald : HudTheme.textMuted,
                hasAlertDot: false
            )
        }
    }

    private func toolTile(
        section: CleanerFocusSection,
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        hasAlertDot: Bool
    ) -> some View {
        let selected = vm.cleanerFocus == section
        return Button {
            vm.cleanerFocus = section
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(accent.opacity(selected ? 0.28 : 0.16))
                            .frame(width: 22, height: 22)
                        Image(systemName: icon)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    Spacer(minLength: 2)
                    if hasAlertDot {
                        Circle()
                            .fill(accent)
                            .frame(width: 6, height: 6)
                    } else if selected {
                        Circle()
                            .fill(accent)
                            .frame(width: 5, height: 5)
                    }
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 10.5, weight: selected ? .black : .bold, design: .rounded))
                        .foregroundStyle(HudTheme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selected || hasAlertDot ? accent : HudTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8.5)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? accent.opacity(0.16) : HudTheme.cardBg.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        selected ? accent.opacity(0.85) : (hasAlertDot ? accent.opacity(0.45) : HudTheme.borderSubtle.opacity(0.55)),
                        lineWidth: selected ? 1.2 : 0.8
                    )
            )
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule()
                        .fill(accent)
                        .frame(height: 2.2)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func outcomeBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(HudTheme.emerald)
            Text(msg)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HudTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                vm.cleanupOutcomeMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(HudTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .cleanCard(accent: HudTheme.emerald, cornerRadius: 8, padding: 9)
    }

    // =========================================================================
    // MARK: - WORKSPACE 1: DỌN SSD (Cache, Build, AI Garbage, Logs & Forecast)
    // =========================================================================
    private var ssdWorkspace: some View {
        let disk = vm.snapshot?.disk
        let selectedBytes = vm.totalSelectedCleanupBytes
        let forecastGB: Double? = disk.map { ($0.availableGB) + (Double(selectedBytes) / 1_073_741_824.0) }

        return VStack(alignment: .leading, spacing: 10) {
            // Unified SSD Summary, Free Space Forecast & Action Card
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 6) {
                            Text("RÁC AN TOÀN CÓ THỂ DỌN")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.textSecondary)
                            if vm.isScanningCleanup {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        Text(Formatters.bytes(vm.totalSafeCacheBytes))
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.emerald)

                        if let disk, let afterGB = forecastGB {
                            HStack(spacing: 5) {
                                Text(String(format: "SSD còn %.1f GB", disk.availableGB))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(HudTheme.textSecondary)
                                if selectedBytes >= 10 * 1_048_576 {
                                    Text("→")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(HudTheme.emerald)
                                    Text(String(format: "Sau dọn ~%.1f GB", afterGB))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(HudTheme.emerald)
                                }
                            }
                        } else {
                            Text("An toàn 100% — không xoá code, mật khẩu, Extension hay database.")
                                .font(.system(size: 10))
                                .foregroundStyle(HudTheme.textMuted)
                        }
                    }

                    Spacer()

                    HudButton(
                        title: vm.isCleaning ? "Đang dọn..." : "Dọn ngay (\(Formatters.bytes(selectedBytes)))",
                        icon: "sparkles",
                        color: HudTheme.emerald,
                        filled: true,
                        compact: false,
                        disabled: vm.isCleaning || selectedBytes == 0
                    ) {
                        vm.runSelectedCleanup()
                    }
                }

                Rectangle().fill(HudTheme.borderSubtle.opacity(0.35)).frame(height: 0.7)

                HStack(spacing: 7) {
                    HudButton(title: "Chọn tất cả an toàn", color: HudTheme.cyan, filled: false, compact: true) {
                        vm.selectAllSafe()
                    }
                    HudButton(title: "Bỏ chọn", color: HudTheme.textSecondary, filled: false, compact: true) {
                        vm.deselectAll()
                    }
                    Spacer()
                    HudButton(
                        title: vm.isScanningCleanup ? "Đang quét..." : "Quét lại SSD",
                        icon: "arrow.clockwise",
                        color: HudTheme.textSecondary,
                        filled: false,
                        compact: true,
                        disabled: vm.isScanningCleanup
                    ) {
                        vm.scanCleanup()
                    }
                }
            }
            .hudCard(accent: HudTheme.emerald, chamfer: 10, padding: 11, showBrackets: true)

            // Clean Collapsible Category Accordions
            cleanupAccordion(
                key: "ai",
                icon: "sparkles",
                title: "Rác AI & Công cụ Dev AI",
                color: HudTheme.violet,
                totalBytes: vm.totalAIGarbageBytes,
                items: vm.aiCandidates
            )
            cleanupAccordion(
                key: "browser",
                icon: "globe",
                title: "Cache Trình duyệt",
                color: HudTheme.cyan,
                totalBytes: vm.totalBrowserCacheBytes,
                items: vm.browserCandidates
            )
            cleanupAccordion(
                key: "dev",
                icon: "hammer.fill",
                title: "Cache Lập trình & Build",
                color: HudTheme.amber,
                totalBytes: vm.totalDeveloperBuildBytes,
                items: vm.developerCandidates
            )
            cleanupAccordion(
                key: "logs",
                icon: "doc.text.fill",
                title: "Log, Crash Reports & Thùng rác",
                color: HudTheme.amber,
                totalBytes: vm.totalLogsAndTrashBytes,
                items: vm.logAndTrashCandidates
            )
            cleanupAccordion(
                key: "storage",
                icon: "folder.fill",
                title: "Dữ liệu dung lượng lớn (Chỉ xem Finder)",
                color: HudTheme.cobalt,
                totalBytes: vm.totalHeavyStorageBytes,
                items: vm.storageHeavyCandidates
            )
        }
    }

    @ViewBuilder
    private func cleanupAccordion(
        key: String,
        icon: String,
        title: String,
        color: Color,
        totalBytes: UInt64,
        items: [CleanupCandidate]
    ) -> some View {
        if !items.isEmpty {
            let isExpanded = !collapsedGroups.contains(key)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if isExpanded {
                        collapsedGroups.insert(key)
                    } else {
                        collapsedGroups.remove(key)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                            .frame(width: 16)

                        Text(title)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(HudTheme.textPrimary)

                        Text("\(items.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(HudTheme.insetBg, in: Capsule())
                            .foregroundStyle(HudTheme.textMuted)

                        Spacer()

                        Text(Formatters.bytes(totalBytes))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(color)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(HudTheme.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(HudTheme.cardBg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HudTheme.borderSubtle.opacity(0.42), lineWidth: 0.75))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    LazyVStack(spacing: 4.5) {
                        ForEach(items) { item in
                            CleanupRowView(item: item, vm: vm, maxSizeBytes: vm.maxCandidateSizeBytes)
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }

    // =========================================================================
    // MARK: - WORKSPACE 2: GIẢI PHÓNG RAM (Smart 1-Click Boost + 4-Layer Matrix)
    // =========================================================================
    private var ramWorkspace: some View {
        let mem = vm.snapshot?.memory
        let eligibleIdle = vm.eligibleIdleAppsNow
        let idleRAMBytes = eligibleIdle.reduce(UInt64(0)) { $0 + $1.rssBytes }
        let orphanBot = vm.orphanAutomationGroup
        let dupExtraCount = vm.duplicateTabExtraCount

        let ramHealth: (label: String, color: Color) = {
            guard let m = mem else { return ("ĐANG ĐO", HudTheme.cyan) }
            if m.compressedGB >= 5.0 || m.swapUsedGB >= 6.0 { return ("ÁP LỰC CAO", HudTheme.crimson) }
            if m.compressedGB >= 3.0 || m.swapUsedGB >= 2.5 { return ("ĐANG NÉN", HudTheme.amber) }
            return ("THÔNG THOÁNG", HudTheme.emerald)
        }()

        let hasSafeQuickTargets = !eligibleIdle.isEmpty || orphanBot != nil || dupExtraCount > 0

        return VStack(alignment: .leading, spacing: 10) {
            // 1. Smart RAM Boost Hero Cockpit
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 6) {
                            Text("BỘ NHỚ RAM HỆ THỐNG")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.textSecondary)
                            Text(ramHealth.label)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(ramHealth.color.opacity(0.18), in: Capsule())
                                .foregroundStyle(ramHealth.color)
                        }

                        if let mem {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(String(format: "%.1f GB trống", mem.availableGB))
                                    .font(.system(size: 21, weight: .black, design: .monospaced))
                                    .foregroundStyle(ramHealth.color == HudTheme.emerald ? HudTheme.cyan : ramHealth.color)
                                Text(String(format: "/ %.0f GB", mem.totalGB))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(HudTheme.textMuted)
                            }
                        }
                    }

                    Spacer()

                    HudButton(
                        title: vm.isBoostingRAM ? "Đang tối ưu..." : "Giải phóng RAM ngay",
                        icon: "bolt.fill",
                        color: HudTheme.cyan,
                        filled: true,
                        compact: false,
                        disabled: vm.isBoostingRAM || vm.isCleaning || vm.isRescuingChrome
                    ) {
                        vm.smartBoostRAM()
                    }
                }

                // Segmented Memory Bar + 4-Layer Breakdown Matrix
                if let mem {
                    SegmentedMemoryBar(memory: mem, height: 7)

                    HStack(spacing: 6) {
                        ramBreakdownCell(label: "ỨNG DỤNG", value: String(format: "%.1f GB", mem.appMemoryGB), color: HudTheme.cyan)
                        ramBreakdownCell(label: "HỆ THỐNG", value: String(format: "%.1f GB", mem.wiredGB), color: HudTheme.violet)
                        ramBreakdownCell(label: "RAM NÉN", value: String(format: "%.1f GB", mem.compressedGB), color: mem.compressedGB >= 4.0 ? HudTheme.amber : HudTheme.textSecondary)
                        ramBreakdownCell(label: "SWAP SSD", value: String(format: "%.1f GB", mem.swapUsedGB), color: mem.swapUsedGB >= 4.0 ? HudTheme.crimson : HudTheme.textSecondary)
                    }
                }

                Rectangle().fill(HudTheme.borderSubtle.opacity(0.35)).frame(height: 0.7)

                // Quick RAM Secondary Actions
                HStack(spacing: 7) {
                    HudButton(
                        title: vm.isScanningTabs ? "Đang quét..." : "Soi & đóng từng tab",
                        icon: "macwindow",
                        color: HudTheme.cyan,
                        filled: false,
                        compact: true,
                        disabled: vm.isScanningTabs
                    ) {
                        vm.scanBrowserTabs()
                    }

                    if dupExtraCount > 0 {
                        HudButton(title: "Xoá \(dupExtraCount) tab trùng", icon: "square.on.square", color: HudTheme.amber, filled: false, compact: true) {
                            vm.closeDuplicateExtras()
                        }
                    }

                    if !eligibleIdle.isEmpty {
                        HudButton(title: "Tắt \(eligibleIdle.count) app rảnh", icon: "moon.zzz.fill", color: HudTheme.violet, filled: false, compact: true) {
                            vm.closeIdleAppsNow()
                        }
                    }

                    Spacer()
                }
            }
            .hudCard(accent: ramHealth.color == HudTheme.emerald ? HudTheme.cyan : ramHealth.color, chamfer: 10, padding: 11, showBrackets: true)

            // Last Smart RAM Boost Result Banner
            if let summary = vm.lastRAMBoostSummary {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundStyle(HudTheme.cyan)
                    Text(summary)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(HudTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        vm.lastRAMBoostSummary = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.bold())
                            .foregroundStyle(HudTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .cleanCard(accent: HudTheme.cyan, cornerRadius: 8, padding: 9)
            }

            // 2. Section A: Safe 1-Click Reclaimable Targets Preview
            if hasSafeQuickTargets {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("AN TOÀN DỌN NGAY (0% MẤT VIỆC)")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.emerald)
                        Spacer()
                        Text("Được gom khi bấm Giải phóng RAM ngay")
                            .font(.system(size: 9))
                            .foregroundStyle(HudTheme.textMuted)
                    }

                    if !eligibleIdle.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(HudTheme.violet)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(eligibleIdle.count) ứng dụng rảnh lâu không dùng")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(HudTheme.textPrimary)
                                Text(eligibleIdle.prefix(4).map(\.name).joined(separator: ", "))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(HudTheme.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("~\(Formatters.bytes(idleRAMBytes))")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(HudTheme.violet)
                            HudButton(title: "Đóng êm", color: HudTheme.violet, filled: false, compact: true) {
                                vm.closeIdleAppsNow()
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                    }

                    if let bot = orphanBot {
                        HStack(spacing: 8) {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(HudTheme.amber)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Cụm Chrome headless / Bot chạy ngầm (\(bot.processCount) tiến trình)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(HudTheme.textPrimary)
                                Text("Dừng sạch bot ngầm không ảnh hưởng Chrome thường đang mở")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(HudTheme.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(Formatters.bytes(bot.totalRSSBytes))
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(HudTheme.amber)
                            HudButton(title: "Dừng Bot", color: HudTheme.amber, filled: true, compact: true) {
                                vm.resetBrowserAutomation()
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                    }

                    if dupExtraCount > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "square.on.square.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(HudTheme.cyan)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(dupExtraCount) tab trình duyệt mở trùng URL")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(HudTheme.textPrimary)
                                Text("Giữ nguyên 1 bản gốc của mỗi trang, chỉ đóng bản lặp thừa")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(HudTheme.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            HudButton(title: "Xoá bản trùng", color: HudTheme.cyan, filled: false, compact: true) {
                                vm.closeDuplicateExtras()
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .cleanCard(accent: HudTheme.emerald.opacity(0.65), cornerRadius: 9, padding: 10)
            }

            // 3. Section B: Top 15 RAM-Heavy Applications (With RAM % Column)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ỨNG DỤNG ĐANG CHIẾM RAM NHIỀU NHẤT")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                    Spacer()
                    Text("RAM (% TỔNG)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HudTheme.textMuted)
                        .frame(width: 86, alignment: .trailing)
                    Text("XỬ LÝ")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HudTheme.textMuted)
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.horizontal, 8)

                if vm.ramReclaimableGroups.isEmpty {
                    Text("Không có ứng dụng nào chiếm RAM bất thường.")
                        .font(.caption)
                        .foregroundStyle(HudTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .cleanCard(padding: 14)
                } else {
                    LazyVStack(spacing: 4.5) {
                        ForEach(vm.ramReclaimableGroups) { group in
                            ProcessRowView(group: group, vm: vm, highlightRAM: true)
                        }
                    }
                }
            }
        }
    }

    private func ramBreakdownCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textMuted)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7.5)
        .padding(.vertical, 5.5)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // =========================================================================
    // MARK: - WORKSPACE 3: SỬA CHROME (4 Clear Numbered Modules)
    // =========================================================================
    private var chromeWorkspace: some View {
        let replayd = vm.replaydProcessGroup
        let isReplaydStuck = vm.isReplaydStuck
        let stuckCount = vm.stuckChromeRenderers.count
        let totalStuckCPU = vm.stuckChromeRenderers.reduce(0.0) { $0 + $1.cpuPercent }
        let chromeGPUCPU = vm.chromeGPUTotalCPU
        let chromeGPUCount = vm.chromeGPUProcesses.count
        let totalChromeProcs = vm.processGroups.first(where: { $0.id == "app:Google Chrome" })?.processCount ?? 0
        let autoGroup = vm.orphanAutomationGroup

        return VStack(alignment: .leading, spacing: 9) {
            // Concise Isolation Guarantee Strip
            HStack(spacing: 7) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(HudTheme.emerald)
                Text("Cô lập an toàn: Giữ nguyên Extension, mật khẩu & tab đang mở. Sửa Chrome thường không chạm bot ngầm.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HudTheme.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HudTheme.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(HudTheme.emerald.opacity(0.28), lineWidth: 0.7))

            // 01 :: macOS replayd XPC Storm
            rescueModuleCard(
                number: "01",
                title: "Sửa bão XPC macOS replayd",
                statusText: {
                    if let r = replayd, isReplaydStuck {
                        let niceTag = vm.isReplaydThrottled ? " • NICE+20" : ""
                        return "\(String(format: "%.0f%%", r.totalCPUPercent)) CPU\(niceTag)"
                    }
                    return "ỔN ĐỊNH (0%)"
                }(),
                statusColor: isReplaydStuck ? HudTheme.crimson : HudTheme.emerald,
                highlight: isReplaydStuck,
                description: isReplaydStuck
                    ? (vm.isReplaydThrottled
                        ? "Đã hạ ưu tiên replayd xuống nice +20. Các app khách (Chrome / OpenMausBot / ChatGPT) vẫn đang nối XPC — bấm Restart sạch Chrome & Dừng Bot để cắt hẳn."
                        : "Tiến trình /usr/libexec/replayd đang kẹt vòng lặp XPC, bóp nghẹt Chrome & OpenMausBot. Bấm reset để khởi tạo lại sạch mà không đóng tab.")
                    : "Khởi tạo lại dịch vụ macOS replayd khi tiến trình này treo CPU và làm chậm Chrome."
            ) {
                HudButton(
                    title: isReplaydStuck ? "Reset replayd ngay (0 mất tab)" : "Kiểm tra & Reset replayd",
                    icon: "bolt.shield.fill",
                    color: isReplaydStuck ? HudTheme.crimson : HudTheme.cyan,
                    filled: isReplaydStuck,
                    compact: true,
                    disabled: vm.isRescuingChrome
                ) {
                    vm.restartStuckReplayd(forceAlways: true)
                }
            }

            // 02 :: Stuck JS/DOM Tabs & Chrome GPU
            let hasTabOrGPUIssue = stuckCount > 0 || chromeGPUCPU >= 8.0
            rescueModuleCard(
                number: "02",
                title: "Gỡ tab đơ JS/DOM & Reset GPU Chrome",
                statusText: {
                    if stuckCount > 0 && chromeGPUCPU >= 8.0 {
                        return "\(stuckCount) TAB • GPU \(String(format: "%.0f%%", chromeGPUCPU))"
                    } else if stuckCount > 0 {
                        return "\(stuckCount) TAB ĐƠ (\(String(format: "%.0f%%", totalStuckCPU)))"
                    } else if chromeGPUCPU >= 8.0 {
                        return "GPU \(String(format: "%.0f%%", chromeGPUCPU)) CPU"
                    }
                    return "ỔN ĐỊNH"
                }(),
                statusColor: hasTabOrGPUIssue ? HudTheme.amber : HudTheme.emerald,
                highlight: hasTabOrGPUIssue,
                description: "Gỡ tab bị vòng lặp JS/DOM (hiện Aw Snap để F5) hoặc Reset tiến trình GPU Chrome (tự hồi trong <0.5s, 0 mất tab)."
            ) {
                HStack(spacing: 7) {
                    HudButton(
                        title: stuckCount > 0 ? "Gỡ \(stuckCount) tab đơ" : "Gỡ tab đơ JS/DOM",
                        icon: "bolt.fill",
                        color: stuckCount > 0 ? HudTheme.amber : HudTheme.cyan,
                        filled: stuckCount > 0,
                        compact: true
                    ) {
                        vm.killStuckChromeRenderers(forceAll: false)
                    }

                    if chromeGPUCount > 0 {
                        HudButton(
                            title: "Reset GPU Chrome",
                            icon: "cpu",
                            color: chromeGPUCPU >= 8.0 ? HudTheme.amber : HudTheme.cyan,
                            filled: chromeGPUCPU >= 8.0,
                            compact: true
                        ) {
                            vm.resetChromeGPUProcess()
                        }
                    }

                    if totalChromeProcs > 0 {
                        HudButton(title: "Gỡ mọi renderer", color: HudTheme.textSecondary, filled: false, compact: true) {
                            vm.killStuckChromeRenderers(forceAll: true)
                        }
                    }
                }
            }

            // 03 :: Headless Bot & Automation Rescue
            rescueModuleCard(
                number: "03",
                title: "Dừng cụm Bot ngầm (OpenMausBot / MCP)",
                statusText: autoGroup.map { "\($0.processCount) PROC • \(Formatters.bytes($0.totalRSSBytes))" } ?? "KHÔNG CÓ",
                statusColor: autoGroup != nil ? HudTheme.amber : HudTheme.textMuted,
                highlight: autoGroup != nil,
                description: "Dừng sạch các tiến trình Chrome headless chạy ngầm và gỡ khoá profile tự động mà không đụng Chrome thường."
            ) {
                HudButton(
                    title: autoGroup != nil ? "Dừng & Reset cụm Bot" : "Reset sạch Automation",
                    icon: "arrow.counterclockwise.circle.fill",
                    color: autoGroup != nil ? HudTheme.amber : HudTheme.cyan,
                    filled: autoGroup != nil,
                    compact: true,
                    disabled: vm.isRescuingChrome || vm.isCleaning
                ) {
                    vm.resetBrowserAutomation()
                }
            }

            // 04 :: Clean Chrome Restart
            rescueModuleCard(
                number: "04",
                title: "Khởi động lại sạch Google Chrome",
                statusText: totalChromeProcs > 0 ? "\(totalChromeProcs) TIẾN TRÌNH" : "CHƯA MỞ",
                statusColor: HudTheme.cobalt,
                highlight: false,
                description: "Đóng êm 2.4s để lưu trọn phiên tab, tự reset replayd, gỡ SingletonLock & dọn OS cache tạm rồi mở lại Chrome."
            ) {
                HStack(spacing: 7) {
                    HudButton(
                        title: vm.isRescuingChrome ? "Đang xử lý..." : "Restart sạch Chrome",
                        icon: "arrow.clockwise",
                        color: HudTheme.cobalt,
                        filled: true,
                        compact: true,
                        disabled: vm.isRescuingChrome || vm.isCleaning
                    ) {
                        vm.rescueAndCleanChrome(relaunch: true)
                    }

                    HudButton(
                        title: "Chỉ tắt & gỡ lock",
                        color: HudTheme.textSecondary,
                        filled: false,
                        compact: true,
                        disabled: vm.isRescuingChrome || vm.isCleaning
                    ) {
                        vm.rescueAndCleanChrome(relaunch: false)
                    }
                }
            }
        }
    }

    private func rescueModuleCard<Actions: View>(
        number: String,
        title: String,
        statusText: String,
        statusColor: Color,
        highlight: Bool,
        description: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(number)
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background((highlight ? statusColor : HudTheme.cyan).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(highlight ? statusColor : HudTheme.cyan)

                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(HudTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(statusText)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(HudTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            actions()
        }
        .cleanCard(accent: highlight ? statusColor : nil, cornerRadius: 9, padding: 10)
    }

    // =========================================================================
    // MARK: - WORKSPACE 4: TỰ ĐỘNG (AUTOPILOT)
    // =========================================================================
    private var autopilotWorkspace: some View {
        let enabled = vm.autoOptimizeConfig.isEnabled
        let cardAccent: Color = vm.isAutoOptimizing ? HudTheme.cyan : (enabled ? HudTheme.emerald : HudTheme.textMuted)
        let eligibleIdle = vm.eligibleIdleAppsNow

        return VStack(alignment: .leading, spacing: 10) {
            // 1. Master Control Card
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("AUTOPILOT TỰ ĐỘNG TỐI ƯU")
                                .font(.system(size: 11.5, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.textPrimary)
                            Text(vm.isAutoOptimizing ? "ĐANG CHẠY" : (enabled ? "ĐANG BẬT" : "ĐANG TẮT"))
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(cardAccent.opacity(0.18), in: Capsule())
                                .foregroundStyle(cardAccent)
                        }
                        Text("Tự dọn cache cũ, đóng êm app rảnh & hạ ưu tiên nền mà không ảnh hưởng công việc.")
                            .font(.system(size: 10))
                            .foregroundStyle(HudTheme.textSecondary)
                    }

                    Spacer()

                    Button {
                        vm.autoOptimizeConfig.isEnabled.toggle()
                    } label: {
                        ZStack(alignment: enabled ? .trailing : .leading) {
                            Capsule()
                                .fill(enabled ? HudTheme.emerald.opacity(0.28) : HudTheme.insetBg)
                                .overlay(Capsule().strokeBorder(enabled ? HudTheme.emerald.opacity(0.85) : HudTheme.textMuted.opacity(0.45), lineWidth: 1))
                                .frame(width: 38, height: 20)
                            Circle()
                                .fill(enabled ? HudTheme.emerald : HudTheme.textMuted)
                                .frame(width: 14, height: 14)
                                .padding(.horizontal, 3)
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 7) {
                    autopilotStatCell(label: "ĐÃ DỌN SSD", value: Formatters.bytes(vm.autoOptimizeLifetimeFreedBytes), accent: HudTheme.emerald)
                    autopilotStatCell(
                        label: "APP RẢNH",
                        value: vm.autoOptimizeTotalIdleAppsClosed > 0
                            ? "\(vm.autoOptimizeTotalIdleAppsClosed) app"
                            : "\(eligibleIdle.count) sẵn sàng",
                        accent: eligibleIdle.isEmpty ? HudTheme.cyan : HudTheme.amber
                    )
                    autopilotStatCell(label: "LỊCH KẾ TIẾP", value: vm.autoOptimizeNextRunLabel, accent: enabled ? HudTheme.textPrimary : HudTheme.textMuted)
                }

                HStack(spacing: 7) {
                    HudButton(
                        title: vm.isAutoOptimizing ? "Đang tối ưu..." : "Chạy tối ưu ngay",
                        icon: "bolt.fill",
                        color: HudTheme.emerald,
                        filled: true,
                        compact: true,
                        disabled: vm.isAutoOptimizing || vm.isCleaning || vm.isRescuingChrome
                    ) {
                        vm.runAutoOptimizeNow()
                    }

                    if !eligibleIdle.isEmpty {
                        HudButton(title: "Tắt \(eligibleIdle.count) app rảnh ngay", icon: "moon.zzz.fill", color: HudTheme.amber, filled: false, compact: true) {
                            vm.closeIdleAppsNow()
                        }
                    }
                }
            }
            .hudCard(accent: cardAccent, chamfer: 10, padding: 11, showBrackets: true)

            // 2. Schedule & Threshold Selectors
            VStack(alignment: .leading, spacing: 7) {
                Text("LỊCH TRÌNH & NGƯỠNG TỰ ĐỘNG")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)

                autopilotIntSelector(title: "Chu kỳ chạy", options: [(1, "1h"), (2, "2h"), (6, "6h"), (12, "12h"), (24, "24h")], selection: $vm.autoOptimizeConfig.intervalHours, accent: HudTheme.cyan)
                autopilotIntSelector(title: "Xoá cache cũ hơn", options: [(1, "1 ngày"), (3, "3 ngày"), (7, "7 ngày"), (14, "14 ngày")], selection: $vm.autoOptimizeConfig.staleCacheDays, accent: HudTheme.emerald)
                autopilotIntSelector(title: "Tắt app rảnh sau", options: [(30, "30p"), (60, "1h"), (120, "2h"), (240, "4h")], selection: $vm.autoOptimizeConfig.idleAppTimeoutMinutes, accent: HudTheme.violet)
                autopilotDoubleSelector(title: "Chạy sớm khi SSD <", options: [(20.0, "20 GB"), (30.0, "30 GB"), (40.0, "40 GB")], selection: $vm.autoOptimizeConfig.lowDiskTriggerGB, accent: HudTheme.amber)
            }
            .cleanCard(padding: 10)

            // 3. Concise Automation Rules
            VStack(alignment: .leading, spacing: 8) {
                Text("QUY TẮC TỐI ƯU")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)

                HudToggleRow(title: "Tự chữa bão macOS replayd (≥ 75% CPU)", subtitle: "Reset sạch hoặc hạ nice +20 — không đóng tab Chrome.", isOn: $vm.autoOptimizeConfig.autoHealStuckReplayd, accent: HudTheme.crimson)
                HudToggleRow(title: "Tự đóng êm app lâu không dùng (Cmd+Q)", subtitle: "Chỉ đóng khi rảnh & CPU < 2%, bỏ qua app công việc & file chưa lưu.", isOn: $vm.autoOptimizeConfig.autoCloseIdleApps, accent: HudTheme.violet)
                HudToggleRow(title: "Hạ ưu tiên nền Spotlight / Photos / iCloud", subtitle: "Đặt nice +10 khi chạy nền ≥ 5% CPU (không tắt tiến trình).", isOn: $vm.autoOptimizeConfig.autoThrottleBackgroundHogs, accent: HudTheme.cyan)
                HudToggleRow(title: "Dọn cache quá hạn (Trình duyệt, AI, Dev)", isOn: $vm.autoOptimizeConfig.autoCleanStaleCaches, accent: HudTheme.emerald)
                HudToggleRow(title: "Dọn rác cập nhật ShipIt, OpenMausBot & QuickLook", isOn: $vm.autoOptimizeConfig.autoCleanUpdaterGarbage, accent: HudTheme.emerald)
                HudToggleRow(title: "Cắt rỗng log LocalWP phình to (> 15 MB)", isOn: $vm.autoOptimizeConfig.autoTruncateOversizedLogs, accent: HudTheme.cyan)
                HudToggleRow(title: "Dọn thư mục /tmp bot mồ côi (Playwright / MCP)", isOn: $vm.autoOptimizeConfig.autoCleanOrphanTempProfiles, accent: HudTheme.cyan)
            }
            .cleanCard(padding: 10)

            // 4. Work-Safe App Protection Matrix
            if !vm.trackedGUIApps.isEmpty {
                let now = Date()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("BẢO VỆ ỨNG DỤNG CÔNG VIỆC")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.textSecondary)
                        Spacer()
                        Text("Bấm nút để khoá / cho phép tự tắt")
                            .font(.system(size: 9))
                            .foregroundStyle(HudTheme.textMuted)
                    }

                    LazyVStack(spacing: 4) {
                        ForEach(vm.trackedGUIApps.prefix(10)) { app in
                            idleAppRow(app, now: now)
                        }
                    }
                }
                .cleanCard(padding: 10)
            }

            // 5. Recent History
            if !vm.autoOptimizeHistory.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NHẬT KÝ GẦN ĐÂY")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)

                    ForEach(vm.autoOptimizeHistory.prefix(4)) { rec in
                        autopilotHistoryRow(rec)
                    }
                }
                .cleanCard(padding: 10)
            }
        }
    }

    private func autopilotStatCell(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(HudTheme.textMuted)
            Text(value)
                .font(.system(size: 11.5, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func idleAppRow(_ app: TrackedGUIApp, now: Date) -> some View {
        let isProtected = vm.isAppWorkProtected(app)
        let idleMins = app.idleMinutes(relativeTo: now)
        let isSystemLocked = (app.bundleID == "com.apple.finder" || app.bundleID == "com.ducdung.MacPulse")
        let isEligible = !isProtected && !app.isFrontmost && app.cpuPercent < 2.0 && idleMins >= vm.autoOptimizeConfig.idleAppTimeoutMinutes

        let idleText: String = app.isFrontmost ? "Đang dùng" : (idleMins == 0 ? "Vừa dùng" : (idleMins >= 60 ? "Rảnh \(idleMins / 60)h\(idleMins % 60)p" : "Rảnh \(idleMins)p"))

        return HStack(spacing: 7) {
            Circle()
                .fill(isEligible ? HudTheme.amber : (isProtected ? HudTheme.emerald : HudTheme.cyan))
                .frame(width: 5.5, height: 5.5)

            Text(app.name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HudTheme.textPrimary)
                .lineLimit(1)

            Text(idleText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(isEligible ? HudTheme.amber : HudTheme.textMuted)

            Spacer(minLength: 4)

            if app.rssBytes > 0 {
                Text(Formatters.bytes(app.rssBytes))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
            }

            Button {
                vm.toggleAppWorkProtection(bundleID: app.bundleID)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isProtected ? "lock.shield.fill" : "moon.zzz.fill")
                        .font(.system(size: 8.5, weight: .bold))
                    Text(isProtected ? "Bảo vệ" : "Tự tắt")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background((isProtected ? HudTheme.emerald : HudTheme.violet).opacity(0.16), in: Capsule())
                .foregroundStyle(isProtected ? HudTheme.emerald : HudTheme.violet)
            }
            .buttonStyle(.plain)
            .disabled(isSystemLocked)
            .opacity(isSystemLocked ? 0.5 : 1.0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
    }

    private func autopilotIntSelector(title: String, options: [(Int, String)], selection: Binding<Int>, accent: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(HudTheme.textSecondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(options, id: \.0) { val, label in
                    let active = selection.wrappedValue == val
                    Button {
                        selection.wrappedValue = val
                    } label: {
                        Text(label)
                            .font(.system(size: 9.5, weight: active ? .bold : .medium, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(active ? accent.opacity(0.22) : HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(active ? accent.opacity(0.75) : HudTheme.borderSubtle.opacity(0.35), lineWidth: 0.7))
                            .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func autopilotDoubleSelector(title: String, options: [(Double, String)], selection: Binding<Double>, accent: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(HudTheme.textSecondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(options, id: \.0) { val, label in
                    let active = abs(selection.wrappedValue - val) < 0.1
                    Button {
                        selection.wrappedValue = val
                    } label: {
                        Text(label)
                            .font(.system(size: 9.5, weight: active ? .bold : .medium, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(active ? accent.opacity(0.22) : HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(active ? accent.opacity(0.75) : HudTheme.borderSubtle.opacity(0.35), lineWidth: 0.7))
                            .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func autopilotHistoryRow(_ rec: AutoOptimizeRunRecord) -> some View {
        let badgeColor: Color
        switch rec.trigger {
        case .replaydStorm: badgeColor = HudTheme.crimson
        case .lowDisk, .ramPressure: badgeColor = HudTheme.amber
        case .manual: badgeColor = HudTheme.cyan
        case .scheduled: badgeColor = HudTheme.emerald
        }
        return HStack(spacing: 6) {
            Text(rec.trigger.rawValue.uppercased())
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(badgeColor.opacity(0.18), in: Capsule())
                .foregroundStyle(badgeColor)

            Text(Self.historyDateFormatter.string(from: rec.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(HudTheme.textMuted)

            Text(rec.summary)
                .font(.system(size: 9.5))
                .foregroundStyle((rec.freedBytes > 0 || !rec.closedIdleApps.isEmpty || rec.throttledBackgroundCount > 0 || rec.restartedReplayd) ? HudTheme.textPrimary : HudTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Clean Minimalist Cleanup Row
private struct CleanupRowView: View {
    let item: CleanupCandidate
    @ObservedObject var vm: AppViewModel
    let maxSizeBytes: UInt64

    private var itemIcon: (name: String, color: Color) {
        let id = item.id.lowercased()
        if id.contains("openmaus") { return ("cpu", HudTheme.amber) }
        if id.contains("ai") || id.contains("cursor") || id.contains("codex") || id.contains("claude") || id.contains("gemini") {
            return ("sparkles", HudTheme.violet)
        }
        if id.contains("chrome") { return ("globe", HudTheme.cyan) }
        if id.contains("brave") { return ("shield.lefthalf.filled", HudTheme.amber) }
        if id.contains("firefox") { return ("flame.fill", HudTheme.amber) }
        if id.contains("safari") { return ("safari", HudTheme.cyan) }
        if id.contains("edge") { return ("globe.americas.fill", HudTheme.teal) }
        if id.contains("arc") { return ("globe.europe.africa.fill", HudTheme.cobalt) }
        if id.contains("vscode") { return ("chevron.left.forwardslash.chevron.right", HudTheme.cyan) }
        if id.contains("brew") || id.contains("homebrew") { return ("cup.and.saucer.fill", HudTheme.amber) }
        if id.contains("npm") || id.contains("yarn") || id.contains("pnpm") || id.contains("composer") || id.contains("bun") { return ("shippingbox.fill", HudTheme.crimson) }
        if id.contains("swiftpm") || id.contains("xcode") || id.contains("go-build") { return ("hammer.fill", HudTheme.amber) }
        if id.contains("pip") || id.contains("uv") || id.contains("python") { return ("terminal.fill", HudTheme.cobalt) }
        if id.contains("trash") { return ("trash.fill", HudTheme.crimson) }
        if id.contains("diagnostic") || id.contains("log") { return ("doc.text.fill", HudTheme.amber) }
        if id.contains("db") || id.contains("brain") { return ("cylinder.split.1x2.fill", HudTheme.violet) }
        if id.contains("playwright") || id.contains("puppeteer") { return ("globe.badge.chevron.backward", HudTheme.cobalt) }
        if id.contains("quicklook") { return ("eye.fill", HudTheme.teal) }
        return ("tray.full.fill", HudTheme.emerald)
    }

    var body: some View {
        let isSelected = vm.selectedCleanupIDs.contains(item.id)
        return HStack(spacing: 8) {
            if item.tier == .safeAutoClean {
                Button {
                    vm.toggleCleanupSelection(item.id)
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? HudTheme.cyan : HudTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 13))
                    .foregroundStyle(HudTheme.cobalt)
                    .frame(width: 20, height: 20)
            }

            Image(systemName: itemIcon.name)
                .font(.system(size: 12))
                .foregroundStyle(itemIcon.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HudTheme.textPrimary)
                        .lineLimit(1)

                    if item.tier == .inspectOnly {
                        Text("CHỈ XEM")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(HudTheme.cobalt.opacity(0.18), in: Capsule())
                            .foregroundStyle(HudTheme.cobalt)
                    } else if !item.defaultSelected {
                        Text("TỰ CHỌN")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(HudTheme.amber.opacity(0.18), in: Capsule())
                            .foregroundStyle(HudTheme.amber)
                    }
                }
                Text(item.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(HudTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            Text(Formatters.bytes(item.sizeBytes))
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(HudTheme.textPrimary)

            Button {
                let firstPath = item.path.split(separator: "|").first.map(String.init) ?? item.path
                vm.revealInFinder(firstPath)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                    .foregroundStyle(HudTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Mở thư mục trong Finder")
        }
        .cleanCard(accent: isSelected ? HudTheme.cyan.opacity(0.55) : nil, cornerRadius: 7, padding: 7.5)
    }
}
