import SwiftUI
import MacPulseCore

struct CleanerView: View {
    @ObservedObject var vm: AppViewModel
    @State private var isRescueManuallyExpanded: Bool = false
    @State private var isAutopilotSettingsExpanded: Bool = false

    private var visibleFilter: CleanerFocusSection {
        vm.cleanerFocus
    }

    private var hasActiveBrowserAlert: Bool {
        vm.isReplaydStuck || vm.orphanAutomationGroup != nil || !vm.stuckChromeRenderers.isEmpty || vm.chromeGPUTotalCPU >= 8.0
    }

    private var isRescueExpanded: Bool {
        hasActiveBrowserAlert || isRescueManuallyExpanded || visibleFilter == .browser
    }

    var body: some View {
        VStack(spacing: 0) {
            cleanerFilterHeader
                .padding(.horizontal, 14)
                .padding(.top, 7)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    if let pending = vm.pendingTerminationGroup {
                        InlineConfirmTerminationCard(group: pending, vm: vm)
                    }

                    if vm.showTabInspector {
                        BrowserTabsInspectorCard(vm: vm)
                    }

                    if let msg = vm.cleanupOutcomeMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(HudTheme.emerald)
                            Text(msg)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HudTheme.emerald)
                            Spacer()
                            Button {
                                vm.cleanupOutcomeMessage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(HudTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .hudCard(accent: HudTheme.emerald, chamfer: 7, padding: 9)
                    }

                    if visibleFilter == .all {
                        autopilotOptimizerCard
                    }

                    heroSummaryCard

                    if visibleFilter == .all || visibleFilter == .browser {
                        chromeRescueCard
                    }

                    if visibleFilter == .all || visibleFilter == .ai {
                        aiSection
                    }

                    if visibleFilter == .all || visibleFilter == .browser {
                        browserSection
                    }

                    if visibleFilter == .all || visibleFilter == .developer {
                        developerSection
                    }

                    if visibleFilter == .all || visibleFilter == .logs {
                        logsSection
                    }

                    if visibleFilter == .all || visibleFilter == .storage {
                        storageHeavySection
                    }

                    if visibleFilter == .all || visibleFilter == .ram {
                        ramSection
                    }
                }
                .padding(14)
            }

            Rectangle()
                .fill(LinearGradient(colors: [.clear, HudTheme.cyan.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)
            cleanerFooterBar
        }
    }

    // MARK: - Filter Bar
    private var cleanerFilterHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                filterButton("Tất cả", section: .all, countText: Formatters.bytes(vm.totalSafeCacheBytes))
                filterButton("Rác AI", section: .ai, countText: Formatters.bytes(vm.totalAIGarbageBytes))
                filterButton("Trình duyệt", section: .browser, countText: Formatters.bytes(vm.totalBrowserCacheBytes))
                filterButton("Lập trình", section: .developer, countText: Formatters.bytes(vm.totalDeveloperBuildBytes))
                filterButton("Log & Rác", section: .logs, countText: Formatters.bytes(vm.totalLogsAndTrashBytes))
                filterButton("Bộ nhớ lớn", section: .storage, countText: Formatters.bytes(vm.totalHeavyStorageBytes))
                filterButton("RAM", section: .ram, countText: Formatters.bytes(vm.estimatedReclaimableRAMBytes))
            }
            .padding(3)
        }
        .background(HudTheme.insetBg, in: ChamferedRect(cut: 6, cornerRadius: 3))
        .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(HudTheme.cyan.opacity(0.22), lineWidth: 0.75))
    }

    private func filterButton(_ label: String, section: CleanerFocusSection, countText: String) -> some View {
        let active = vm.cleanerFocus == section
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                vm.cleanerFocus = section
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: section.icon)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(active ? HudTheme.cyan : HudTheme.textMuted)
                Text(label)
                    .font(.system(size: 10.5, weight: active ? .bold : .medium))
                    .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                if countText != "0 B" && countText != "0.0 B" {
                    Text(countText)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(active ? HudTheme.cyan.opacity(0.24) : HudTheme.cardBg, in: Capsule())
                        .foregroundStyle(active ? HudTheme.cyan : HudTheme.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(active ? HudTheme.cyan.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(active ? HudTheme.cyan.opacity(0.55) : .clear, lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let historyDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm dd/MM"
        return df
    }()

    // MARK: - Autopilot Background Auto-Optimizer Card
    private var autopilotOptimizerCard: some View {
        let enabled = vm.autoOptimizeConfig.isEnabled
        let cardAccent: Color = vm.isAutoOptimizing ? HudTheme.cyan : (enabled ? HudTheme.emerald : HudTheme.textMuted)
        let statusText: String = vm.isAutoOptimizing ? "BOOSTING" : (enabled ? "ONLINE" : "STANDBY")
        let eligibleIdle = vm.eligibleIdleAppsNow

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ZStack {
                    ChamferedRect(cut: 6, cornerRadius: 3)
                        .fill(cardAccent.opacity(0.20))
                        .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(cardAccent.opacity(0.6), lineWidth: 0.8))
                        .frame(width: 30, height: 30)
                    Image(systemName: "bolt.shield.fill")
                        .foregroundStyle(cardAccent)
                        .font(.system(size: 13.5, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("AUTOPILOT TĂNG TỐC & TỰ DỌN")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.textPrimary)

                        Text(statusText)
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(cardAccent.opacity(0.20), in: Capsule())
                            .foregroundStyle(cardAccent)
                    }
                    Text("Quét mỗi \(vm.autoOptimizeConfig.intervalHours)h • Cache >\(vm.autoOptimizeConfig.staleCacheDays)d • Tắt app rảnh >\(vm.autoOptimizeConfig.idleAppTimeoutMinutes)p • Hạ ưu tiên nền.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Quick Master Switch
                Button {
                    vm.autoOptimizeConfig.isEnabled.toggle()
                } label: {
                    ZStack(alignment: enabled ? .trailing : .leading) {
                        Capsule()
                            .fill(enabled ? HudTheme.emerald.opacity(0.28) : HudTheme.insetBg)
                            .overlay(
                                Capsule()
                                    .strokeBorder(enabled ? HudTheme.emerald.opacity(0.85) : HudTheme.textMuted.opacity(0.45), lineWidth: 1)
                            )
                            .frame(width: 36, height: 19)
                        Circle()
                            .fill(enabled ? HudTheme.emerald : HudTheme.textMuted)
                            .frame(width: 13, height: 13)
                            .padding(.horizontal, 3)
                    }
                }
                .buttonStyle(.plain)
                .help(enabled ? "Tắt chế độ Tự động tối ưu ngầm" : "Bật chế độ Tự động tối ưu ngầm")
            }

            // Compact 3-cell HUD Telemetry Row
            HStack(spacing: 7) {
                autopilotMetricCell(
                    label: "ĐÃ TỰ DỌN SSD",
                    value: Formatters.bytes(vm.autoOptimizeLifetimeFreedBytes),
                    accent: HudTheme.emerald
                )
                autopilotMetricCell(
                    label: "APP RẢNH / RAM",
                    value: vm.autoOptimizeTotalIdleAppsClosed > 0
                        ? "\(vm.autoOptimizeTotalIdleAppsClosed) app • \(Formatters.bytes(vm.autoOptimizeLifetimeReclaimedRAMBytes))"
                        : "\(eligibleIdle.count) sẵn sàng",
                    accent: eligibleIdle.isEmpty ? HudTheme.cyan : HudTheme.amber
                )
                autopilotMetricCell(
                    label: "LỊCH KẾ TIẾP",
                    value: vm.autoOptimizeNextRunLabel,
                    accent: enabled ? HudTheme.textPrimary : HudTheme.textMuted
                )
            }

            // Action Bar
            HStack(spacing: 7) {
                HudButton(
                    title: vm.isAutoOptimizing ? "Đang tăng tốc..." : "Turbo Boost ngay",
                    icon: "bolt.fill",
                    color: HudTheme.emerald,
                    filled: true,
                    compact: true,
                    disabled: vm.isAutoOptimizing || vm.isCleaning || vm.isRescuingChrome
                ) {
                    vm.runAutoOptimizeNow()
                }

                if !eligibleIdle.isEmpty {
                    HudButton(
                        title: "Tắt \(eligibleIdle.count) app rảnh",
                        icon: "moon.zzz.fill",
                        color: HudTheme.amber,
                        filled: false,
                        compact: true
                    ) {
                        vm.closeIdleAppsNow()
                    }
                }

                HudButton(
                    title: isAutopilotSettingsExpanded ? "Ẩn cài đặt" : "Cấu hình & App rảnh",
                    icon: isAutopilotSettingsExpanded ? "chevron.up" : "slider.horizontal.3",
                    color: HudTheme.cyan,
                    filled: false,
                    compact: true
                ) {
                    vm.refreshTrackedGUIApps()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAutopilotSettingsExpanded.toggle()
                    }
                }

                Spacer()

                Text("\(vm.autoOptimizeConfig.intervalHours)H • >\(vm.autoOptimizeConfig.staleCacheDays)D")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textMuted)
            }

            if isAutopilotSettingsExpanded {
                autopilotSettingsPanel
            }
        }
        .hudCard(accent: cardAccent, chamfer: 10, padding: 11, showBrackets: true)
    }

    private func autopilotMetricCell(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(HudTheme.textMuted)
            Text(value)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.cyan.opacity(0.16), lineWidth: 0.7))
    }

    private var autopilotSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle()
                .fill(HudTheme.cyan.opacity(0.18))
                .frame(height: 0.7)

            // Parameter Selectors
            VStack(alignment: .leading, spacing: 6) {
                autopilotIntSelector(
                    title: "Chu kỳ quét tự động",
                    options: [(1, "1 giờ"), (2, "2 giờ"), (6, "6 giờ"), (12, "12 giờ"), (24, "24 giờ")],
                    selection: $vm.autoOptimizeConfig.intervalHours,
                    accent: HudTheme.cyan
                )
                autopilotIntSelector(
                    title: "Xoá cache cũ hơn",
                    options: [(1, "1 ngày"), (3, "3 ngày"), (7, "7 ngày"), (14, "14 ngày")],
                    selection: $vm.autoOptimizeConfig.staleCacheDays,
                    accent: HudTheme.emerald
                )
                autopilotIntSelector(
                    title: "Tự tắt app rảnh sau",
                    options: [(30, "30p"), (60, "1 giờ"), (120, "2 giờ"), (240, "4 giờ")],
                    selection: $vm.autoOptimizeConfig.idleAppTimeoutMinutes,
                    accent: HudTheme.violet
                )
                autopilotDoubleSelector(
                    title: "Tự kích hoạt khi SSD <",
                    options: [(20.0, "20 GB"), (30.0, "30 GB"), (40.0, "40 GB")],
                    selection: $vm.autoOptimizeConfig.lowDiskTriggerGB,
                    accent: HudTheme.amber
                )
            }
            .padding(8)
            .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.cyan.opacity(0.16), lineWidth: 0.7))

            // 7 Granular Rule Switches
            VStack(spacing: 7) {
                HudToggleRow(
                    title: "Tự chữa lỗi treo macOS replayd (≥ 75% CPU bóp Chrome)",
                    subtitle: "Phát hiện bão XPC (_Xmach_notify_port_destroyed) và restart replayd ngay kể cả khi CPU tổng đang cao — 0 mất tab.",
                    isOn: $vm.autoOptimizeConfig.autoHealStuckReplayd,
                    accent: HudTheme.crimson
                )
                HudToggleRow(
                    title: "Tự đóng êm ứng dụng lâu không dùng (Cmd+Q an toàn)",
                    subtitle: "Chỉ đóng khi không dùng ≥ \(vm.autoOptimizeConfig.idleAppTimeoutMinutes)p & CPU < 2%. Tự bảo vệ công việc & không ép tắt file chưa lưu.",
                    isOn: $vm.autoOptimizeConfig.autoCloseIdleApps,
                    accent: HudTheme.violet
                )
                HudToggleRow(
                    title: "Hạ ưu tiên tiến trình nền ngốn CPU (Spotlight / Photos / iCloud)",
                    subtitle: "Đặt nice +10 cho tác vụ chỉ mục/đồng bộ chạy nền ≥ 5% CPU để thao tác luôn mượt (không tắt app).",
                    isOn: $vm.autoOptimizeConfig.autoThrottleBackgroundHogs,
                    accent: HudTheme.cyan
                )
                HudToggleRow(
                    title: "Dọn cache cũ quá hạn (Trình duyệt, AI, Dev)",
                    subtitle: "Chỉ xoá tệp không dùng quá \(vm.autoOptimizeConfig.staleCacheDays) ngày trong ~/Library/Caches & .npm/.cache.",
                    isOn: $vm.autoOptimizeConfig.autoCleanStaleCaches,
                    accent: HudTheme.emerald
                )
                HudToggleRow(
                    title: "Dọn rác cập nhật ShipIt, OpenMausBot & QuickLook",
                    subtitle: "Tự dọn bản vá/update cũ và bộ đệm ảnh xem nhanh Finder.",
                    isOn: $vm.autoOptimizeConfig.autoCleanUpdaterGarbage,
                    accent: HudTheme.emerald
                )
                HudToggleRow(
                    title: "Tự cắt rỗng file log LocalWP phình to (>15 MB)",
                    subtitle: "Truncate trực tiếp giữ nguyên file, không ảnh hưởng website hay database.",
                    isOn: $vm.autoOptimizeConfig.autoTruncateOversizedLogs,
                    accent: HudTheme.cyan
                )
                HudToggleRow(
                    title: "Dọn thư mục /tmp bot mồ côi (Playwright / agent-browser)",
                    subtitle: "Chỉ xoá thư mục cũ >30p không có tiến trình nào đang sử dụng.",
                    isOn: $vm.autoOptimizeConfig.autoCleanOrphanTempProfiles,
                    accent: HudTheme.cyan
                )
            }
            .padding(9)
            .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.cyan.opacity(0.16), lineWidth: 0.7))

            // Interactive Idle App & Work-Safety Whitelist Matrix
            if !vm.trackedGUIApps.isEmpty {
                idleAppsProtectionSection
            }

            // Safety Guardrail Banner
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(HudTheme.emerald)
                    .font(.caption)
                Text("Bảo vệ tuyệt đối công việc: Tự hoãn khi CPU ≥ 65%. Mặc định khoá bảo vệ Chrome, Warp, Terminal, Antigravity, LocalWP, OpenMausBot, Slack, Telegram, Zalo & Remote/VPS. Chỉ gửi Cmd+Q lịch sự (không ép tắt mất file).")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(HudTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HudTheme.emerald.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.emerald.opacity(0.30), lineWidth: 0.7))

            // Recent History
            if !vm.autoOptimizeHistory.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NHẬT KÝ TỐI ƯU GẦN ĐÂY")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(HudTheme.textMuted)

                    ForEach(vm.autoOptimizeHistory.prefix(4)) { rec in
                        autopilotHistoryRow(rec)
                    }
                }
            }
        }
    }

    private var idleAppsProtectionSection: some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("ỨNG DỤNG ĐANG MỞ & BẢO VỆ CÔNG VIỆC")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(HudTheme.violet)
                Spacer()
                Text("Bấm nút khiên để khoá/mở tự tắt")
                    .font(.system(size: 8.5))
                    .foregroundStyle(HudTheme.textMuted)
            }

            LazyVStack(spacing: 4) {
                ForEach(vm.trackedGUIApps.prefix(10)) { app in
                    idleAppRow(app, now: now)
                }
            }
        }
        .padding(8)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.violet.opacity(0.28), lineWidth: 0.7))
    }

    private func idleAppRow(_ app: TrackedGUIApp, now: Date) -> some View {
        let isProtected = vm.isAppWorkProtected(app)
        let idleMins = app.idleMinutes(relativeTo: now)
        let isSystemLocked = (app.bundleID == "com.apple.finder" || app.bundleID == "com.ducdung.MacPulse")
        let isEligible = !isProtected && !app.isFrontmost && app.cpuPercent < 2.0 && idleMins >= vm.autoOptimizeConfig.idleAppTimeoutMinutes

        let idleText: String
        if app.isFrontmost {
            idleText = "Đang dùng"
        } else if idleMins == 0 {
            idleText = "Vừa dùng"
        } else if idleMins >= 60 {
            idleText = "Rảnh \(idleMins / 60)h \(idleMins % 60)p"
        } else {
            idleText = "Rảnh \(idleMins)p"
        }

        return HStack(spacing: 7) {
            Circle()
                .fill(isEligible ? HudTheme.amber : (isProtected ? HudTheme.emerald : HudTheme.cyan))
                .frame(width: 5.5, height: 5.5)

            Text(app.name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HudTheme.textPrimary)
                .lineLimit(1)

            Text(idleText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(isEligible ? HudTheme.amber : HudTheme.textMuted)

            Spacer(minLength: 4)

            if app.rssBytes > 0 {
                Text(Formatters.bytes(app.rssBytes))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
            }

            Button {
                vm.toggleAppWorkProtection(bundleID: app.bundleID)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isProtected ? "lock.shield.fill" : "moon.zzz.fill")
                        .font(.system(size: 8.5, weight: .bold))
                    Text(isProtected ? "Bảo vệ" : "Tự tắt")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background((isProtected ? HudTheme.emerald : HudTheme.violet).opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder((isProtected ? HudTheme.emerald : HudTheme.violet).opacity(0.55), lineWidth: 0.65))
                .foregroundStyle(isProtected ? HudTheme.emerald : HudTheme.violet)
            }
            .buttonStyle(.plain)
            .disabled(isSystemLocked)
            .opacity(isSystemLocked ? 0.55 : 1.0)
            .help(isProtected ? "Đang bảo vệ (không bao giờ tự tắt) — bấm để cho phép tự tắt khi rảnh" : "Cho phép tự tắt êm khi rảnh — bấm để khoá bảo vệ công việc")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4.5)
        .background(HudTheme.cardBg.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
    }

    private func autopilotIntSelector(
        title: String,
        options: [(Int, String)],
        selection: Binding<Int>,
        accent: Color
    ) -> some View {
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
                            .font(.system(size: 9.5, weight: active ? .black : .semibold, design: .monospaced))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 3)
                            .background(active ? accent.opacity(0.24) : HudTheme.cardBg, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(active ? accent.opacity(0.75) : HudTheme.textMuted.opacity(0.25), lineWidth: 0.7))
                            .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func autopilotDoubleSelector(
        title: String,
        options: [(Double, String)],
        selection: Binding<Double>,
        accent: Color
    ) -> some View {
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
                            .font(.system(size: 9.5, weight: active ? .black : .semibold, design: .monospaced))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 3)
                            .background(active ? accent.opacity(0.24) : HudTheme.cardBg, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(active ? accent.opacity(0.75) : HudTheme.textMuted.opacity(0.25), lineWidth: 0.7))
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
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(badgeColor.opacity(0.18), in: Capsule())
                .foregroundStyle(badgeColor)

            Text(Self.historyDateFormatter.string(from: rec.timestamp))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(HudTheme.textMuted)

            Text(rec.summary)
                .font(.system(size: 9.5))
                .foregroundStyle((rec.freedBytes > 0 || !rec.closedIdleApps.isEmpty || rec.throttledBackgroundCount > 0 || rec.restartedReplayd) ? HudTheme.textPrimary : HudTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4.5)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Hero Telemetry Summary
    private var heroSummaryCard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(HudTheme.violet)
                        Text("RÁC AN TOÀN SSD")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(HudTheme.textSecondary)
                        Spacer()
                        if vm.isScanningCleanup {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    Text(Formatters.bytes(vm.totalSafeCacheBytes))
                        .font(.system(size: 19, weight: .black, design: .monospaced))
                        .foregroundStyle(HudTheme.violet)
                    Text("Cache AI, trình duyệt & build — 0% mất code/tài khoản")
                        .font(.system(size: 9.5))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudCard(accent: HudTheme.violet, chamfer: 9, padding: 10, showBrackets: true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(HudTheme.cyan)
                        Text("RAM KHẢ DỤNG")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(HudTheme.textSecondary)
                    }
                    if let mem = vm.snapshot?.memory {
                        Text(String(format: "%.1f GB TRỐNG", mem.availableGB))
                            .font(.system(size: 19, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.cyan)
                        SegmentedMemoryBar(memory: mem, height: 4.5)
                    }
                    Text("Thu hồi ~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes)) từ app thừa")
                        .font(.system(size: 9.5))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudCard(accent: HudTheme.cyan, chamfer: 9, padding: 10, showBrackets: true)
            }

            HStack(spacing: 7) {
                HudButton(title: "Chọn tất cả an toàn", color: HudTheme.cyan, filled: false, compact: true) {
                    vm.selectAllSafe()
                }
                HudButton(title: "Bỏ chọn", color: HudTheme.textSecondary, filled: false, compact: true) {
                    vm.deselectAll()
                }

                Spacer()

                if vm.totalSelectedCleanupBytes > 0 {
                    HudButton(
                        title: vm.isCleaning ? "Đang dọn..." : "Dọn ngay (\(Formatters.bytes(vm.totalSelectedCleanupBytes)))",
                        icon: "trash.slash.fill",
                        color: HudTheme.emerald,
                        filled: true,
                        compact: false,
                        disabled: vm.isCleaning
                    ) {
                        vm.runSelectedCleanup()
                    }
                }
            }
        }
    }

    // MARK: - Smart Collapsible Chrome & Automation Rescue Hub
    private var chromeRescueCard: some View {
        let chromeCacheSize = vm.browserCandidates.first(where: { $0.id == "cache-chrome" })?.sizeBytes ?? 0
        let stuckCount = vm.stuckChromeRenderers.count
        let totalStuckCPU = vm.stuckChromeRenderers.reduce(0.0) { $0 + $1.cpuPercent }
        let totalChromeProcs = vm.processGroups.first(where: { $0.id == "app:Google Chrome" })?.processCount ?? 0
        let chromeGPUCPU = vm.chromeGPUTotalCPU
        let chromeGPUCount = vm.chromeGPUProcesses.count
        let replayd = vm.replaydProcessGroup
        let isReplaydStuck = vm.isReplaydStuck
        let autoGroup = vm.orphanAutomationGroup
        let cardAccent: Color = isReplaydStuck ? HudTheme.crimson : (hasActiveBrowserAlert ? HudTheme.amber : HudTheme.cyan)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRescueManuallyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        ChamferedRect(cut: 6, cornerRadius: 3)
                            .fill(cardAccent.opacity(0.20))
                            .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(cardAccent.opacity(0.6), lineWidth: 0.8))
                            .frame(width: 30, height: 30)
                        Image(systemName: hasActiveBrowserAlert ? "exclamationmark.shield.fill" : "lifepreserver.fill")
                            .foregroundStyle(cardAccent)
                            .font(.system(size: 14, weight: .bold))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("CHROME & AUTOMATION RESCUE")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.textPrimary)
                            if isReplaydStuck, let r = replayd {
                                Text("REPLAYD \(Int(r.totalCPUPercent.rounded()))% CPU")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(HudTheme.crimson.opacity(0.24), in: Capsule())
                                    .foregroundStyle(HudTheme.crimson)
                            } else if let auto = autoGroup {
                                Text("\(auto.processCount) BOT NGẦM")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(HudTheme.amber.opacity(0.22), in: Capsule())
                                    .foregroundStyle(HudTheme.amber)
                            } else if stuckCount > 0 {
                                Text("\(stuckCount) TAB ĐƠ")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(HudTheme.amber.opacity(0.22), in: Capsule())
                                    .foregroundStyle(HudTheme.amber)
                            } else if chromeGPUCPU >= 8.0 {
                                Text("GPU \(Int(chromeGPUCPU.rounded()))% CPU")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(HudTheme.amber.opacity(0.22), in: Capsule())
                                    .foregroundStyle(HudTheme.amber)
                            } else {
                                Text("NOMINAL")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(HudTheme.emerald.opacity(0.18), in: Capsule())
                                    .foregroundStyle(HudTheme.emerald)
                            }
                        }
                        Text(isReplaydStuck
                             ? "Bão XPC macOS replayd đang bóp nghẹt Chrome & OpenMausBot — bấm Reset replayd ngay (0 mất tab)."
                             : (hasActiveBrowserAlert
                                ? "Phát hiện tab JS/DOM, GPU Chrome hoặc cụm headless ngầm ngốn tải — bấm xử lý tức thì."
                                : "Chữa bão replayd XPC, gỡ đơ tab JS/DOM & GPU Chrome, hoặc reset cụm agent-browser."))
                            .font(.system(size: 10))
                            .foregroundStyle(HudTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if chromeCacheSize > 0 {
                        Text(Formatters.bytes(chromeCacheSize))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(HudTheme.cyan)
                    }

                    Image(systemName: isRescueExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(cardAccent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isRescueExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(HudTheme.emerald)
                        .font(.caption)
                    Text("Cô lập tuyệt đối: Không mất Extension, không mất tab/cookie, gỡ đơ Chrome thường không chạm bot ngầm.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HudTheme.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HudTheme.emerald.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.emerald.opacity(0.32), lineWidth: 0.7))

                // Action 0: macOS replayd XPC Storm Fix (Choking Chrome, OpenMausBot & WindowServer)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: isReplaydStuck ? "flame.fill" : "waveform.path.ecg")
                            .foregroundStyle(isReplaydStuck ? HudTheme.crimson : HudTheme.cyan)
                        Text("Chữa bão XPC macOS replayd (Bóp nghẹt Chrome & OpenMausBot)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HudTheme.textPrimary)
                        Spacer()
                        if let r = replayd {
                            let pidText = r.pids.first.map { "PID \($0) • " } ?? ""
                            let niceTag = vm.isReplaydThrottled ? " • NICE+20" : ""
                            Text("\(pidText)\(String(format: "%.0f%%", r.totalCPUPercent)) CPU\(niceTag)")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(isReplaydStuck ? HudTheme.crimson : HudTheme.emerald)
                        } else {
                            Text("0% CPU • ỔN ĐỊNH")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(HudTheme.emerald)
                        }
                    }

                    Text(isReplaydStuck
                        ? (vm.isReplaydThrottled
                            ? "MacPulse đã hạ ưu tiên replayd xuống nice +20 để giữ thao tác mượt, nhưng các app khách (Chrome / OpenMausBot headless / ChatGPT / Codex) vẫn kẹt vòng lặp XPC RPDaemonProxy. Khởi động lại sạch Chrome + Reset Automation (hoặc mở lại ChatGPT/Codex) để cắt hẳn bão XPC."
                            : "/usr/libexec/replayd đang kẹt vòng lặp XPC (_Xmach_notify_port_destroyed), đốt 20–27% CPU trên Chrome chính + 15–19% mỗi Chrome headless. Bấm Reset để launchctl kickstart sạch (và tự hạ nice +20 nếu app khách vẫn spam) — không đóng 1 tab nào!")
                        : "Khi tiến trình macOS /usr/libexec/replayd bị treo vòng lặp XPC, nó bóp nghẹt Chrome, OpenMausBot & WindowServer. Bấm reset để launchd khởi động lại sạch ở 0% CPU (giữ nguyên mọi tab).")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                .padding(9)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isReplaydStuck ? HudTheme.crimson.opacity(0.65) : HudTheme.cyan.opacity(0.20), lineWidth: isReplaydStuck ? 1.1 : 0.8))

                // Action 1: Stuck Renderers (JS/DOM loops) & Chrome GPU Soft Reset
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: (stuckCount > 0 || chromeGPUCPU >= 8.0) ? "exclamationmark.triangle.fill" : "bolt.horizontal.fill")
                            .foregroundStyle((stuckCount > 0 || chromeGPUCPU >= 8.0) ? HudTheme.amber : HudTheme.cyan)
                        Text("Gỡ đơ tab JS/DOM & GPU Chrome thường (Localhost / Theme)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HudTheme.textPrimary)
                        Spacer()
                        HStack(spacing: 5) {
                            if stuckCount > 0 {
                                Text("\(stuckCount) TAB • \(String(format: "%.0f%%", totalStuckCPU)) CPU")
                                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                    .foregroundStyle(HudTheme.amber)
                            }
                            if chromeGPUCPU >= 5.0 {
                                Text("GPU \(String(format: "%.0f%%", chromeGPUCPU))")
                                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                    .foregroundStyle(chromeGPUCPU >= 8.0 ? HudTheme.amber : HudTheme.cyan)
                            }
                        }
                    }

                    Text("Tự bắt tab kẹt vòng lặp JS/DOM (≥10% CPU hoặc ≥8% CPU & ≥250 MB RAM) và cho phép Reset GPU Chrome (tự hồi sinh trong <0.5s, 0 mất tab, giữ nguyên Extension và bot headless).")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 7) {
                        HudButton(
                            title: stuckCount > 0 ? "Gỡ kẹt ngay (\(stuckCount) tab)" : "Gỡ tab đơ JS/DOM",
                            icon: "bolt.fill",
                            color: stuckCount > 0 ? HudTheme.amber : HudTheme.cyan,
                            filled: true,
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
                .padding(9)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder((stuckCount > 0 || chromeGPUCPU >= 8.0) ? HudTheme.amber.opacity(0.48) : HudTheme.cyan.opacity(0.20), lineWidth: 0.8))

                // Action 2: Full Clean Restart
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(HudTheme.cobalt)
                        Text("Khởi động lại sạch Chrome (Đóng êm 2.4s • Gỡ lock • Chữa replayd)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HudTheme.textPrimary)
                    }

                    Text("Đóng nhẹ nhàng để lưu trọn phiên tab, tự chữa replayd nếu đang treo, gỡ sạch SingletonLock & DevToolsActivePort, dọn OS cache tạm và mở lại Chrome mượt mà.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        HudButton(
                            title: vm.isRescuingChrome ? "Đang cứu Chrome..." : "Khởi động lại sạch Chrome",
                            icon: "arrow.clockwise",
                            color: HudTheme.cobalt,
                            filled: true,
                            compact: true,
                            disabled: vm.isRescuingChrome || vm.isCleaning
                        ) {
                            vm.rescueAndCleanChrome(relaunch: true)
                        }

                        HudButton(
                            title: "Chỉ tắt & dọn lock",
                            color: HudTheme.textSecondary,
                            filled: false,
                            compact: true,
                            disabled: vm.isRescuingChrome || vm.isCleaning
                        ) {
                            vm.rescueAndCleanChrome(relaunch: false)
                        }
                    }
                }
                .padding(9)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.cobalt.opacity(0.25), lineWidth: 0.8))

                // Action 3: Automation & agent-browser Rescue
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: autoGroup != nil ? "exclamationmark.octagon.fill" : "terminal.fill")
                            .foregroundStyle(autoGroup != nil ? HudTheme.amber : HudTheme.textSecondary)
                        Text("Dừng & Reset Chrome Automation (agent-browser / MCP)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HudTheme.textPrimary)
                        Spacer()
                        if let auto = autoGroup {
                            Text("\(auto.processCount) PROC • \(String(format: "%.0f%%", auto.totalCPUPercent)) CPU • \(Formatters.bytes(auto.totalRSSBytes))")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.amber)
                        }
                    }

                    Text(autoGroup != nil
                        ? "Cụm headless Chrome & agent-browser đang chạy ngầm ngốn tài nguyên. Dừng sạch và gỡ khoá profile tự động mà không đụng Chrome thường."
                        : "Dừng mọi tiến trình Chrome headless / agent-browser ngầm và xoá sạch SingletonLock / DevToolsActivePort.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HudButton(
                        title: autoGroup != nil ? "Dừng & Reset sạch cụm Automation" : "Reset sạch Chrome Automation",
                        icon: "arrow.counterclockwise.circle.fill",
                        color: autoGroup != nil ? HudTheme.amber : HudTheme.cyan,
                        filled: autoGroup != nil,
                        compact: true,
                        disabled: vm.isRescuingChrome || vm.isCleaning
                    ) {
                        vm.resetBrowserAutomation()
                    }
                }
                .padding(9)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(autoGroup != nil ? HudTheme.amber.opacity(0.55) : HudTheme.cyan.opacity(0.20), lineWidth: 0.8))
            }
        }
        .hudCard(accent: cardAccent, chamfer: 10, padding: 11, showBrackets: true)
    }

    // MARK: - Category Sections
    private var aiSection: some View {
        cleanupSectionBlock(
            icon: "sparkles",
            title: "Rác AI (Antigravity, OpenMausBot, Cursor, Codex, Claude)",
            subtitle: "Cache cập nhật ShipIt, logs, bộ đệm GPU/Shader tạm của công cụ AI — 0% mất API key, prompt hay cookie.",
            color: HudTheme.violet,
            totalBytes: vm.totalAIGarbageBytes,
            items: vm.aiCandidates,
            emptyMessage: "Không phát hiện tệp rác AI nào đáng kể."
        )
    }

    private var browserSection: some View {
        cleanupSectionBlock(
            icon: "globe",
            title: "Cache Trình duyệt (Chrome, Brave, Edge, Safari, Arc, Firefox)",
            subtitle: "Chỉ xoá OS Cache tạm (~/Library/Caches). Bảo vệ tuyệt đối 100% Extension, tab, bookmark và tài khoản.",
            color: HudTheme.cyan,
            totalBytes: vm.totalBrowserCacheBytes,
            items: vm.browserCandidates,
            emptyMessage: "Không có cache trình duyệt lớn cần dọn."
        )
    }

    private var developerSection: some View {
        cleanupSectionBlock(
            icon: "hammer.fill",
            title: "Cache Lập trình & Build (Xcode, npm, Homebrew, pip, Composer)",
            subtitle: "Gói tải về và tệp trung gian build — tự tải lại tự động khi bạn chạy build hoặc install.",
            color: HudTheme.amber,
            totalBytes: vm.totalDeveloperBuildBytes,
            items: vm.developerCandidates,
            emptyMessage: "Không có cache lập trình nào cần dọn."
        )
    }

    private var logsSection: some View {
        cleanupSectionBlock(
            icon: "doc.text.fill",
            title: "File Log phình to & Thùng rác",
            subtitle: "Cắt rỗng an toàn log LocalWP lớn, dọn thumbnail QuickLook và Thùng rác (tắt mặc định).",
            color: HudTheme.amber,
            totalBytes: vm.totalLogsAndTrashBytes,
            items: vm.logAndTrashCandidates,
            emptyMessage: "Không có file log phình to hay rác hệ thống."
        )
    }

    private var storageHeavySection: some View {
        cleanupSectionBlock(
            icon: "internaldrive.fill",
            title: "Dữ liệu dung lượng lớn (Chỉ xem Finder)",
            subtitle: "Database, trình duyệt Playwright/Puppeteer hoặc lịch sử phiên AI — MacPulse KHÔNG tự ý xoá.",
            color: HudTheme.cobalt,
            totalBytes: vm.totalHeavyStorageBytes,
            items: vm.storageHeavyCandidates,
            emptyMessage: "Không phát hiện dữ liệu dung lượng lớn (>500 MB) cần kiểm tra."
        )
    }

    private func cleanupSectionBlock(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        totalBytes: UInt64,
        items: [CleanupCandidate],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(
                icon: icon,
                title: title,
                color: color,
                trailingText: Formatters.bytes(totalBytes)
            )
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(HudTheme.textSecondary)

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(HudTheme.textMuted)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
            } else {
                LazyVStack(spacing: 5) {
                    ForEach(items) { item in
                        CleanupRowView(item: item, vm: vm, maxSizeBytes: vm.maxCandidateSizeBytes)
                    }
                }
            }
        }
    }

    private var ramSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionEyebrow(
                icon: "memorychip.fill",
                title: "Giải phóng RAM thực (Ứng dụng đang chạy)",
                color: HudTheme.cyan,
                trailingText: "~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes))"
            )

            Text("Đóng chọn lọc ứng dụng rảnh hoặc tab trùng để giải phóng RAM thật, không dùng lệnh ảo gây khựng hệ thống.")
                .font(.system(size: 10))
                .foregroundStyle(HudTheme.textSecondary)

            HStack(spacing: 8) {
                HudButton(title: "Soi & đóng từng tab", icon: "macwindow", color: HudTheme.cyan, filled: false, compact: true) {
                    vm.scanBrowserTabs()
                }

                if let orphan = vm.orphanAutomationGroup {
                    HudButton(title: "Dừng & Reset Bot (\(Formatters.bytes(orphan.totalRSSBytes)))", color: HudTheme.amber, filled: true, compact: true) {
                        vm.resetBrowserAutomation()
                    }
                }
            }

            LazyVStack(spacing: 5) {
                ForEach(vm.ramReclaimableGroups) { group in
                    ProcessRowView(group: group, vm: vm, highlightRAM: true)
                }
            }
        }
    }

    // MARK: - Footer
    private var cleanerFooterBar: some View {
        HStack {
            HudButton(
                title: vm.isScanningCleanup ? "Đang quét..." : "Quét lại SSD",
                icon: "arrow.clockwise",
                color: HudTheme.cyan,
                filled: false,
                compact: true,
                disabled: vm.isScanningCleanup
            ) {
                vm.scanCleanup()
            }

            Spacer()

            Text("ĐÃ CHỌN: \(Formatters.bytes(vm.totalSelectedCleanupBytes).uppercased())")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(HudTheme.textSecondary)

            HudButton(
                title: vm.isCleaning ? "Đang dọn..." : "Dọn rác đã chọn",
                icon: "sparkles",
                color: HudTheme.emerald,
                filled: true,
                compact: true,
                disabled: vm.isCleaning || vm.totalSelectedCleanupBytes == 0
            ) {
                vm.runSelectedCleanup()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8.5)
        .background(HudTheme.bgDeep.opacity(0.65))
    }
}

// MARK: - Cleanup Row with Glowing Relative Size Bar
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
        if id.contains("npm") || id.contains("yarn") || id.contains("pnpm") || id.contains("composer") { return ("shippingbox.fill", HudTheme.crimson) }
        if id.contains("swiftpm") || id.contains("xcode") { return ("hammer.fill", HudTheme.amber) }
        if id.contains("pip") || id.contains("uv") || id.contains("python") { return ("terminal.fill", HudTheme.cobalt) }
        if id.contains("trash") { return ("trash.fill", HudTheme.crimson) }
        if id.contains("log") { return ("doc.text.fill", HudTheme.amber) }
        if id.contains("db") || id.contains("brain") { return ("cylinder.split.1x2.fill", HudTheme.violet) }
        if id.contains("playwright") || id.contains("puppeteer") { return ("globe.badge.chevron.backward", HudTheme.cobalt) }
        if id.contains("quicklook") { return ("eye.fill", HudTheme.teal) }
        return ("tray.full.fill", HudTheme.emerald)
    }

    private var safetyBadge: (label: String, color: Color) {
        if item.tier == .inspectOnly { return ("CHỈ XEM", HudTheme.cobalt) }
        if item.defaultSelected { return ("AN TOÀN 100%", HudTheme.emerald) }
        return ("TỰ CHỌN", HudTheme.amber)
    }

    private var sizeRatio: Double {
        max(0.04, min(1.0, Double(item.sizeBytes) / Double(max(1, maxSizeBytes))))
    }

    var body: some View {
        let isSelected = vm.selectedCleanupIDs.contains(item.id)
        return HStack(spacing: 9) {
            if item.tier == .safeAutoClean {
                Button {
                    vm.toggleCleanupSelection(item.id)
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15.5))
                        .foregroundStyle(isSelected ? HudTheme.cyan : HudTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "folder.badge.questionmark")
                    .foregroundStyle(HudTheme.cobalt)
                    .frame(width: 20, height: 20)
            }

            Image(systemName: itemIcon.name)
                .font(.system(size: 13))
                .foregroundStyle(itemIcon.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(HudTheme.textPrimary)
                        .lineLimit(1)
                    Text(safetyBadge.label)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(safetyBadge.color.opacity(0.16), in: Capsule())
                        .foregroundStyle(safetyBadge.color)
                }
                Text(item.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(HudTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.bytes(item.sizeBytes))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textPrimary)
                ZStack(alignment: .leading) {
                    Capsule().fill(HudTheme.insetBg)
                    Capsule()
                        .fill(itemIcon.color)
                        .frame(width: max(3, 46 * CGFloat(sizeRatio)))
                }
                .frame(width: 46, height: 3)
            }

            Button {
                let firstPath = item.path.split(separator: "|").first.map(String.init) ?? item.path
                vm.revealInFinder(firstPath)
            } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(HudTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Mở thư mục trong Finder")
        }
        .hudCard(accent: isSelected ? HudTheme.cyan.opacity(0.55) : HudTheme.textMuted.opacity(0.28), chamfer: 6, padding: 8.5)
    }
}
