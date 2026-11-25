import SwiftUI
import MacPulseCore

public struct AIPulseView: View {
    @ObservedObject var vm: AppViewModel

    public init(vm: AppViewModel) {
        self.vm = vm
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(spacing: 12) {
                    headerBanner

                    if let snap = vm.aiSnapshot {
                        if let agy = snap.antigravity {
                            AntigravityCommandCard(metrics: agy, now: context.date)
                        }

                        if let gpt = snap.chatGPT {
                            ChatGPTCommandCard(metrics: gpt, now: context.date)
                        }
                    } else {
                        loadingPlaceholder
                    }

                    efficiencyFootnote
                }
                .padding(14)
            }
        }
        .onAppear {
            if vm.aiSnapshot == nil {
                vm.refreshAIQuota()
            }
        }
    }

    private var headerBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                ChamferedRect(cut: 7, cornerRadius: 3)
                    .fill(HudTheme.antigravityGradient)
                    .frame(width: 36, height: 36)
                    .shadow(color: HudTheme.cyan.opacity(0.45), radius: 6)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("NEURAL QUOTA COMMAND")
                        .font(.system(size: 12.5, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(HudTheme.textPrimary)
                    if vm.isScanningAI {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text("Đo trực tiếp phiên 5 giờ, giới hạn tuần & token thực (Antigravity + ChatGPT)")
                    .font(.system(size: 10))
                    .foregroundStyle(HudTheme.textSecondary)
            }

            Spacer()

            HudButton(
                title: vm.isScanningAI ? "Đang quét" : "Đồng bộ",
                icon: "arrow.clockwise",
                color: HudTheme.cyan,
                filled: true,
                compact: true,
                disabled: vm.isScanningAI
            ) {
                vm.refreshAIQuota()
            }
        }
        .hudCard(accent: HudTheme.cyan, chamfer: 9, padding: 11, showBrackets: true)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.regular)
            Text("CONNECTING TO NEURAL DAEMONS...")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(HudTheme.cyan)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .hudCard(accent: HudTheme.cyan, chamfer: 10, padding: 14)
    }

    private var efficiencyFootnote: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(HudTheme.emerald)
            Text("Quét song song từ Antigravity daemon nội bộ, ChatGPT /wham/usage & SQLite cục bộ. 0% số liệu giả khi offline.")
                .font(.system(size: 10))
                .foregroundStyle(HudTheme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Google Antigravity Hologram Card
private struct AntigravityCommandCard: View {
    let metrics: AIProviderMetrics
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                ZStack {
                    ChamferedRect(cut: 6, cornerRadius: 3)
                        .fill(HudTheme.antigravityGradient)
                        .frame(width: 34, height: 34)
                        .shadow(color: HudTheme.cobalt.opacity(0.55), radius: 5)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 15, weight: .bold))
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
                                .background(HudTheme.cobalt.opacity(0.24), in: Capsule())
                                .overlay(Capsule().strokeBorder(HudTheme.cobalt.opacity(0.6), lineWidth: 0.7))
                                .foregroundStyle(HudTheme.cyan)
                        }
                    }
                    Text(metrics.userAccount ?? metrics.statusMessage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                SourceStateBadge(state: metrics.sourceState, syncTime: metrics.lastSyncTime)
            }

            Rectangle()
                .fill(LinearGradient(colors: [HudTheme.cobalt.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)

            if !metrics.quotaPools.isEmpty {
                VStack(spacing: 8) {
                    ForEach(metrics.quotaPools) { pool in
                        QuotaPoolTelemetryRow(
                            title: pool.label,
                            subtitle: pool.modelSummary,
                            quota: pool.quota,
                            accent: pool.id.contains("gemini") ? HudTheme.cyan : HudTheme.violet,
                            now: now
                        )
                    }
                }
            } else if let q5 = metrics.fiveHourQuota {
                QuotaPoolTelemetryRow(
                    title: q5.name,
                    subtitle: metrics.activeModel ?? "Gemini",
                    quota: q5,
                    accent: HudTheme.cyan,
                    now: now
                )
            } else {
                OfflineQuotaNotice(message: metrics.statusMessage)
            }

            if metrics.promptCreditsAvailable != nil || metrics.flowCreditsAvailable != nil {
                HStack(spacing: 8) {
                    if let pCred = metrics.promptCreditsAvailable {
                        creditPill(label: "PROMPT CREDITS", value: "\(pCred)", color: HudTheme.cyan)
                    }
                    if let fCred = metrics.flowCreditsAvailable {
                        creditPill(label: "FLOW CREDITS", value: "\(fCred)", color: HudTheme.violet)
                    }
                    Spacer()
                }
            }

            TokenStatsMatrix(
                tokens5H: metrics.formattedTokensLast5Hours,
                tokensToday: metrics.formattedTokensToday,
                tokens7D: metrics.formattedTokensLast7Days,
                turnsToday: metrics.turnsOrPromptsToday,
                sessionsToday: metrics.activeSessionsToday,
                accent: HudTheme.cyan
            )
        }
        .hudCard(accent: HudTheme.cobalt, chamfer: 11, padding: 13, showBrackets: true)
    }

    private func creditPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(HudTheme.textSecondary)
            Text(value)
                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(HudTheme.insetBg, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.7))
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
                        .shadow(color: HudTheme.emerald.opacity(0.55), radius: 5)
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
