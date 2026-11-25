import SwiftUI
import MacPulseCore

public struct AIPulseView: View {
    @ObservedObject var vm: AppViewModel

    public init(vm: AppViewModel) {
        self.vm = vm
    }

    public var body: some View {
        let tickInterval: TimeInterval = vm.openCodeRunningSessions.isEmpty ? 30 : 5
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            ScrollView {
                VStack(spacing: 11) {
                    OpenCodeCommandCard(vm: vm, now: context.date)

                    if let snap = vm.aiSnapshot {
                        if let gpt = snap.chatGPT {
                            ChatGPTCommandCard(metrics: gpt, now: context.date)
                        }
                    } else {
                        loadingPlaceholder
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .onAppear {
            vm.openCodeUnreadCompletions = 0
            vm.pollOpenCode(forceRead: true)
            if vm.aiSnapshot == nil {
                vm.refreshAIQuota()
            }
        }
    }

    private var loadingPlaceholder: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text("Đang đồng bộ hạn mức ChatGPT / Codex...")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(HudTheme.cyan)
        }
        .frame(maxWidth: .infinity)
        .cleanCard(padding: 20)
    }
}

// MARK: - OpenCode Live Task Monitor & Completion Notifier Card
private struct OpenCodeCommandCard: View {
    @ObservedObject var vm: AppViewModel
    let now: Date
    @State private var isSettingsExpanded: Bool = false

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    private var isRunningAny: Bool { !vm.openCodeRunningSessions.isEmpty }

    private var cardAccent: Color {
        if !vm.isOpenCodeAvailable { return HudTheme.textMuted }
        if isRunningAny { return HudTheme.cyan }
        return vm.openCodeConfig.isEnabled ? HudTheme.emerald : HudTheme.textMuted
    }

    private var statusBadgeText: String {
        if !vm.isOpenCodeAvailable { return "NOT FOUND" }
        if isRunningAny { return "\(vm.openCodeRunningSessions.count) RUNNING" }
        return vm.openCodeConfig.isEnabled ? "WATCHING" : "MUTED"
    }

    var body: some View {
        let enabled = vm.openCodeConfig.isEnabled
        VStack(alignment: .leading, spacing: 10) {
            // Card Header
            HStack(spacing: 10) {
                ZStack {
                    ChamferedRect(cut: 6, cornerRadius: 3)
                        .fill(cardAccent.opacity(0.22))
                        .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(cardAccent.opacity(0.65), lineWidth: 0.9))
                        .frame(width: 34, height: 34)
                    Image(systemName: isRunningAny ? "terminal.fill" : "bell.badge.fill")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(cardAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("OPENCODE TASK WATCHER")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.textPrimary)

                        HStack(spacing: 4) {
                            LivePulseDot(color: cardAccent, isLive: isRunningAny || (enabled && vm.isOpenCodeAvailable))
                            Text(statusBadgeText)
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .foregroundStyle(cardAccent)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(cardAccent.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(cardAccent.opacity(0.45), lineWidth: 0.7))
                    }

                    Text(isRunningAny
                         ? "Đang có \(vm.openCodeRunningSessions.count) phiên OpenCode chạy — sẽ báo ngay khi xong!"
                         : "Tự phát âm thanh & hiện banner nổi ngay khi task OpenCode hoàn tất hoặc báo lỗi.")
                        .font(.system(size: 10))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Sync button
                Button {
                    vm.pollOpenCode(forceRead: true)
                    vm.refreshAIQuota()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HudTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(vm.isScanningAI)
                .help("Đồng bộ lại OpenCode & ChatGPT Quota")

                // Quick Master Switch
                Button {
                    vm.openCodeConfig.isEnabled.toggle()
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
                .help(enabled ? "Tắt thông báo hoàn tất OpenCode" : "Bật thông báo hoàn tất OpenCode")
            }

            Rectangle()
                .fill(LinearGradient(colors: [cardAccent.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)

            // Active Running Sessions Banner
            if isRunningAny {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ĐANG CHẠY TRỰC TIẾP")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(HudTheme.cyan)

                    let nowMs = Int64(now.timeIntervalSince1970 * 1000)
                    ForEach(vm.openCodeRunningSessions) { session in
                        runningSessionRow(session, nowMs: nowMs)
                    }
                }
            }

            // Action Controls Bar
            HStack(spacing: 7) {
                HudButton(title: "Thử thông báo", icon: "bell.and.waves.left.and.right.fill", color: HudTheme.emerald, filled: true, compact: true) {
                    vm.testOpenCodeAlert()
                }

                HudButton(title: "Mở OpenCode", icon: "terminal", color: HudTheme.cyan, filled: false, compact: true) {
                    vm.focusOpenCodeHost()
                }

                HudButton(
                    title: isSettingsExpanded ? "Ẩn cài đặt" : "Cài đặt",
                    icon: isSettingsExpanded ? "chevron.up" : "slider.horizontal.3",
                    color: HudTheme.textSecondary,
                    filled: false,
                    compact: true
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isSettingsExpanded.toggle()
                    }
                }

                Spacer()

                Text(vm.openCodeConfig.playSound ? "♪ \(vm.openCodeConfig.soundName.uppercased())" : "MUTE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textMuted)
            }

            // Collapsible Settings Panel
            if isSettingsExpanded {
                openCodeSettingsPanel
            }

            // Recent Sessions List
            if !vm.isOpenCodeAvailable {
                OfflineQuotaNotice(message: "Không tìm thấy cơ sở dữ liệu OpenCode (~/.local/share/opencode/opencode.db).")
            } else {
                let completedRecent = vm.openCodeRecentSessions.filter { !$0.isRunning(nowMs: Int64(now.timeIntervalSince1970 * 1000)) }.prefix(5)
                if !completedRecent.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("PHIÊN OPENCODE GẦN ĐÂY")
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(HudTheme.textMuted)
                            Spacer()
                            if !vm.openCodeRecentAlerts.isEmpty {
                                Text("\(vm.openCodeRecentAlerts.count) ĐÃ BÁO")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(HudTheme.emerald)
                            }
                        }

                        ForEach(Array(completedRecent)) { item in
                            completedSessionRow(item)
                        }
                    }
                }
            }
        }
        .hudCard(accent: cardAccent, chamfer: 11, padding: 13, showBrackets: true)
    }

    private func runningSessionRow(_ session: OpenCodeSessionItem, nowMs: Int64) -> some View {
        let elapsed = OpenCodeMonitor.formatDuration(seconds: session.durationSeconds(nowMs: nowMs))
        let modeColor: Color = session.modeBadgeLabel == "PLAN" ? HudTheme.violet : HudTheme.emerald
        return HStack(spacing: 8) {
            LivePulseDot(color: HudTheme.cyan, isLive: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let mode = session.modeBadgeLabel {
                        Text(mode)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(modeColor.opacity(0.22), in: Capsule())
                            .foregroundStyle(modeColor)
                    }
                    Text(session.displayTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HudTheme.textPrimary)
                        .lineLimit(1)
                }
                if let prompt = session.cleanedLatestPrompt, prompt != session.displayTitle {
                    Text("“\(prompt)”")
                        .font(.system(size: 9.5))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HudTheme.cyan)
                    if let model = session.displayModel, !model.isEmpty {
                        Text("•")
                            .foregroundStyle(HudTheme.textMuted)
                        Text(model)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(HudTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            Text(elapsed)
                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(HudTheme.cyan.opacity(0.20), in: Capsule())
                .overlay(Capsule().strokeBorder(HudTheme.cyan.opacity(0.55), lineWidth: 0.7))
                .foregroundStyle(HudTheme.cyan)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(HudTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.cyan.opacity(0.45), lineWidth: 0.8))
    }

    private func completedSessionRow(_ session: OpenCodeSessionItem) -> some View {
        let color: Color
        let icon: String
        switch session.outcome {
        case .succeeded, .unknown:
            color = session.modeBadgeLabel == "PLAN" ? HudTheme.violet : HudTheme.emerald
            icon = session.modeBadgeLabel == "PLAN" ? "doc.text.magnifyingglass" : "checkmark.circle.fill"
        case .failed:
            color = HudTheme.crimson
            icon = "xmark.circle.fill"
        case .interrupted:
            color = HudTheme.amber
            icon = "stop.circle.fill"
        }

        let dur = session.durationSeconds()
        let durText = dur >= 1 ? OpenCodeMonitor.formatDuration(seconds: dur) : "<1s"

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    if let mode = session.modeBadgeLabel {
                        Text(mode)
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(color.opacity(0.18), in: Capsule())
                            .foregroundStyle(color)
                    }
                    Text(session.displayTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(HudTheme.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text(session.projectName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(HudTheme.cyan.opacity(0.85))
                        .lineLimit(1)
                    if let model = session.displayModel {
                        Text("• \(model)")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(HudTheme.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            Text(durText)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5.5)
                .padding(.vertical, 1.5)
                .background(color.opacity(0.14), in: Capsule())
                .foregroundStyle(color)

            Text(Self.timeFormatter.string(from: session.lastActivityDate))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(HudTheme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5.5)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.textMuted.opacity(0.18), lineWidth: 0.6))
    }

    private var openCodeSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sound Picker
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Âm báo khi hoàn tất")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(HudTheme.textSecondary)
                    Spacer()
                    Text("Bấm tên để nghe thử")
                        .font(.system(size: 9))
                        .foregroundStyle(HudTheme.textMuted)
                }
                HStack(spacing: 4) {
                    ForEach(["Glass", "Hero", "Ping", "Submarine", "Pop"], id: \.self) { name in
                        let active = vm.openCodeConfig.playSound && vm.openCodeConfig.soundName == name
                        Button {
                            vm.openCodeConfig.playSound = true
                            vm.previewOpenCodeSound(name)
                        } label: {
                            Text(name)
                                .font(.system(size: 9.5, weight: active ? .black : .semibold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(active ? HudTheme.emerald.opacity(0.24) : HudTheme.cardBg, in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(active ? HudTheme.emerald.opacity(0.75) : HudTheme.textMuted.opacity(0.25), lineWidth: 0.7))
                                .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
            .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))

            // Min Duration Selector
            HStack {
                Text("Chỉ báo task chạy tối thiểu")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(HudTheme.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach([(0, "Mọi task"), (3, ">3s"), (10, ">10s"), (30, ">30s")], id: \.0) { secs, label in
                        let active = vm.openCodeConfig.minDurationSeconds == secs
                        Button {
                            vm.openCodeConfig.minDurationSeconds = secs
                        } label: {
                            Text(label)
                                .font(.system(size: 9.5, weight: active ? .black : .semibold, design: .monospaced))
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background(active ? HudTheme.cyan.opacity(0.24) : HudTheme.cardBg, in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(active ? HudTheme.cyan.opacity(0.75) : HudTheme.textMuted.opacity(0.25), lineWidth: 0.7))
                                .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
            .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))

            // Toggles
            VStack(spacing: 7) {
                HudToggleRow(
                    title: "Chỉ theo dõi OpenCode Terminal của bạn",
                    subtitle: "Tự động lọc sạch các phiên bot ngầm (OpenMausBot / ACP / Gateway) để không báo nhầm.",
                    isOn: $vm.openCodeConfig.onlyInteractiveSessions,
                    accent: HudTheme.emerald
                )
                HudToggleRow(
                    title: "Phát âm thanh báo ngay khi xong",
                    isOn: $vm.openCodeConfig.playSound,
                    accent: HudTheme.emerald
                )
                HudToggleRow(
                    title: "Hiện banner HUD nổi góc phải màn hình",
                    subtitle: "Không cướp con trỏ gõ phím — bấm vào để nhảy ngay tới cửa sổ OpenCode.",
                    isOn: $vm.openCodeConfig.showFloatingBanner,
                    accent: HudTheme.emerald
                )
                HudToggleRow(
                    title: "Gửi thêm vào macOS Notification Center",
                    subtitle: "Khi bật cả hai, banner HUD sẽ tự chuyển xuống góc dưới-phải để không chồng nhau.",
                    isOn: $vm.openCodeConfig.showSystemNotification,
                    accent: HudTheme.cyan
                )
                HudToggleRow(
                    title: "Chỉ báo phiên chính (bỏ qua subagent con)",
                    isOn: $vm.openCodeConfig.onlyTopLevelSessions,
                    accent: HudTheme.cyan
                )
            }
            .padding(9)
            .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

// MARK: - ChatGPT Hologram Card
private struct ChatGPTCommandCard: View {
    let metrics: AIProviderMetrics
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                ZStack {
                    ChamferedRect(cut: 6, cornerRadius: 3)
                        .fill(HudTheme.chatGPTGradient)
                        .frame(width: 34, height: 34)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(metrics.name.uppercased())
                            .font(.system(size: 12.5, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.textPrimary)
                        if let plan = metrics.planTier {
                            Text(plan)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(HudTheme.emerald.opacity(0.22), in: Capsule())
                                .overlay(Capsule().strokeBorder(HudTheme.emerald.opacity(0.55), lineWidth: 0.7))
                                .foregroundStyle(HudTheme.emerald)
                        }
                        if metrics.limitReached {
                            Text("LIMIT REACHED")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(HudTheme.crimson.opacity(0.24), in: Capsule())
                                .foregroundStyle(HudTheme.crimson)
                        }
                    }
                    HStack(spacing: 5) {
                        Text(metrics.userAccount ?? metrics.statusMessage)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HudTheme.textSecondary)
                            .lineLimit(1)
                        if let model = metrics.activeModel {
                            Text("│")
                                .font(.system(size: 9))
                                .foregroundStyle(HudTheme.textMuted)
                            Text(model)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(HudTheme.emerald)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                SourceStateBadge(state: metrics.sourceState, syncTime: metrics.lastSyncTime)
            }

            Rectangle()
                .fill(LinearGradient(colors: [HudTheme.emerald.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)

            if metrics.fiveHourQuota != nil || metrics.weeklyQuota != nil {
                VStack(spacing: 8) {
                    if let q5 = metrics.fiveHourQuota {
                        QuotaPoolTelemetryRow(
                            title: "Phiên 5 Giờ (Burst Window)",
                            subtitle: "Hạn mức ngắn hạn tự hồi sau 5 giờ",
                            quota: q5,
                            accent: HudTheme.emerald,
                            now: now
                        )
                    }

                    if let q7 = metrics.weeklyQuota {
                        QuotaPoolTelemetryRow(
                            title: "Giới Hạn Tuần (7-Day Cap)",
                            subtitle: "Tổng hạn mức sử dụng chu kỳ tuần",
                            quota: q7,
                            accent: HudTheme.teal,
                            now: now
                        )
                    }
                }
            } else {
                OfflineQuotaNotice(message: metrics.statusMessage)
            }

            if let rc = metrics.resetCreditsAvailable, rc > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.caption)
                        .foregroundStyle(HudTheme.emerald)
                    Text("Lượt reset hạn mức dự phòng sẵn có: \(rc)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.emerald.opacity(0.32), lineWidth: 0.7))
            }

            TokenStatsMatrix(
                tokens5H: metrics.formattedTokensLast5Hours,
                tokensToday: metrics.formattedTokensToday,
                tokens7D: metrics.formattedTokensLast7Days,
                turnsToday: 0,
                sessionsToday: metrics.activeSessionsToday,
                accent: HudTheme.emerald
            )
        }
        .hudCard(accent: HudTheme.emerald, chamfer: 11, padding: 13, showBrackets: true)
    }
}

// MARK: - Shared Sci-Fi Subcomponents
private struct SourceStateBadge: View {
    let state: AIQuotaSourceState
    let syncTime: Date

    private var color: Color {
        switch state {
        case .live: return HudTheme.emerald
        case .cached: return HudTheme.amber
        case .offline: return HudTheme.textMuted
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                LivePulseDot(color: color, isLive: state == .live)
                Text(state.badgeLabel)
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 6.5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.7))

            Text(syncTime, style: .time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(HudTheme.textMuted)
        }
    }
}

private struct QuotaPoolTelemetryRow: View {
    let title: String
    let subtitle: String
    let quota: AIWindowQuota
    let accent: Color
    let now: Date

    private var healthColor: Color {
        if quota.usedPercent >= 90 { return HudTheme.crimson }
        if quota.usedPercent >= 70 { return HudTheme.amber }
        return accent
    }

    var body: some View {
        HStack(spacing: 11) {
            QuotaRingView(
                remainingPercent: quota.remainingPercent,
                color: healthColor,
                size: 48,
                lineWidth: 4.2
            )

            VStack(alignment: .leading, spacing: 5.5) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(HudTheme.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(HudTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("CÒN \(quota.formattedRemainingPercent)")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(healthColor)
                        Text("ĐÃ DÙNG \(quota.formattedUsedPercent)")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HudTheme.textMuted)
                    }
                }

                TickProgressBar(
                    ratio: quota.remainingPercent / 100.0,
                    color: healthColor,
                    height: 6.5,
                    showTicks: true,
                    segments: 22
                )

                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 9.5))
                        .foregroundStyle(healthColor)
                    Text("RESET SAU: \(quota.formattedResetCountdown(relativeTo: now).uppercased())")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                    Spacer()
                    if let resetAt = quota.resetAt {
                        Text(resetAt, style: .time)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(HudTheme.textMuted)
                    }
                }
            }
        }
        .padding(9.5)
        .background(HudTheme.insetBg.opacity(0.9), in: ChamferedRect(cut: 7, cornerRadius: 3))
        .overlay(ChamferedRect(cut: 7, cornerRadius: 3).strokeBorder(healthColor.opacity(0.32), lineWidth: 0.8))
    }
}

private struct TokenStatsMatrix: View {
    let tokens5H: String
    let tokensToday: String
    let tokens7D: String
    let turnsToday: Int
    let sessionsToday: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            metricCell(label: "5 GIỜ QUA", value: tokens5H, sub: "tokens")
            metricCell(label: "HÔM NAY", value: tokensToday, sub: turnsToday > 0 ? "\(turnsToday) lượt" : (sessionsToday > 0 ? "\(sessionsToday) phiên" : "tokens"))
            metricCell(label: "7 NGÀY QUA", value: tokens7D, sub: "tổng tuần")
        }
    }

    private func metricCell(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(HudTheme.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textPrimary)
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(accent.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6.5)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(accent.opacity(0.18), lineWidth: 0.65))
    }
}

private struct OfflineQuotaNotice: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13))
                .foregroundStyle(HudTheme.amber)
            Text(message)
                .font(.caption)
                .foregroundStyle(HudTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(HudTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.amber.opacity(0.35), lineWidth: 0.7))
    }
}
