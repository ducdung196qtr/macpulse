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

    // MARK: - Header Banner
    private var headerBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(PulseTheme.antigravityGradient)
                    .frame(width: 34, height: 34)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("AI Quota Command Center")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    if vm.isScanningAI {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text("Đo trực tiếp phiên 5 giờ, giới hạn tuần & token thực (Antigravity + ChatGPT)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                vm.refreshAIQuota()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .bold))
                        .rotationEffect(.degrees(vm.isScanningAI ? 360 : 0))
                        .animation(vm.isScanningAI ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: vm.isScanningAI)
                    Text("Đồng bộ")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(PulseTheme.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(PulseTheme.cyan.opacity(0.32), lineWidth: 0.8))
                .foregroundStyle(PulseTheme.cyan)
            }
            .buttonStyle(.plain)
            .disabled(vm.isScanningAI)
        }
        .telemetryCard(accent: PulseTheme.cobalt, cornerRadius: 11, padding: 11)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.regular)
            Text("Đang đồng bộ quota trực tiếp từ daemon & API...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .telemetryCard(cornerRadius: 12, padding: 14)
    }

    private var efficiencyFootnote: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(PulseTheme.emerald)
            Text("Quét song song từ Antigravity daemon nội bộ, ChatGPT /wham/usage & SQLite cục bộ. Không dùng số liệu giả khi offline.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Google Antigravity Command Card
private struct AntigravityCommandCard: View {
    let metrics: AIProviderMetrics
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Top Identity Row
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(PulseTheme.antigravityGradient)
                        .frame(width: 34, height: 34)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(metrics.name)
                            .font(.system(size: 13.5, weight: .bold))
                        if let plan = metrics.planTier {
                            Text(plan)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PulseTheme.cobalt.opacity(0.18), in: Capsule())
                                .foregroundStyle(PulseTheme.cobalt)
                        }
                    }
                    Text(metrics.userAccount ?? metrics.statusMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                SourceStateBadge(state: metrics.sourceState, syncTime: metrics.lastSyncTime)
            }

            Divider().opacity(0.45)

            // Multi-Pool Quotas (Gemini 4/Flash & Claude 4.6/GPT-OSS)
            if !metrics.quotaPools.isEmpty {
                VStack(spacing: 8) {
                    ForEach(metrics.quotaPools) { pool in
                        QuotaPoolTelemetryRow(
                            title: pool.label,
                            subtitle: pool.modelSummary,
                            quota: pool.quota,
                            accent: pool.id.contains("gemini") ? PulseTheme.cobalt : PulseTheme.violet,
                            now: now
                        )
                    }
                }
            } else if let q5 = metrics.fiveHourQuota {
                QuotaPoolTelemetryRow(
                    title: q5.name,
                    subtitle: metrics.activeModel ?? "Gemini",
                    quota: q5,
                    accent: PulseTheme.cobalt,
                    now: now
                )
            } else {
                OfflineQuotaNotice(message: metrics.statusMessage)
            }

            // Credits Pill Row (if reported by daemon)
            if metrics.promptCreditsAvailable != nil || metrics.flowCreditsAvailable != nil {
                HStack(spacing: 8) {
                    if let pCred = metrics.promptCreditsAvailable {
                        creditPill(label: "Prompt Credits", value: "\(pCred)", color: PulseTheme.cyan)
                    }
                    if let fCred = metrics.flowCreditsAvailable {
                        creditPill(label: "Flow Credits", value: "\(fCred)", color: PulseTheme.violet)
                    }
                    Spacer()
                }
            }

            // Real Timezone-Accurate Token Matrix (5H / Today / 7D)
            TokenStatsMatrix(
                tokens5H: metrics.formattedTokensLast5Hours,
                tokensToday: metrics.formattedTokensToday,
                tokens7D: metrics.formattedTokensLast7Days,
                turnsToday: metrics.turnsOrPromptsToday,
                sessionsToday: metrics.activeSessionsToday,
                accent: PulseTheme.cobalt
            )
        }
        .telemetryCard(accent: PulseTheme.cobalt, cornerRadius: 12, padding: 13)
    }

    private func creditPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(color.opacity(0.11), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.7))
    }
}

// MARK: - ChatGPT Command Card
private struct ChatGPTCommandCard: View {
    let metrics: AIProviderMetrics
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Top Identity Row
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(PulseTheme.chatGPTGradient)
                        .frame(width: 34, height: 34)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(metrics.name)
                            .font(.system(size: 13.5, weight: .bold))
                        if let plan = metrics.planTier {
                            Text(plan)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PulseTheme.emerald.opacity(0.18), in: Capsule())
                                .foregroundStyle(PulseTheme.emerald)
                        }
                        if metrics.limitReached {
                            Text("CHẠM TRẦN")
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(PulseTheme.crimson.opacity(0.2), in: Capsule())
                                .foregroundStyle(PulseTheme.crimson)
                        }
                    }
                    HStack(spacing: 5) {
                        Text(metrics.userAccount ?? metrics.statusMessage)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let model = metrics.activeModel {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(model)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PulseTheme.emerald)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                SourceStateBadge(state: metrics.sourceState, syncTime: metrics.lastSyncTime)
            }

            Divider().opacity(0.45)

            // 5-Hour & Weekly Windows
            if metrics.fiveHourQuota != nil || metrics.weeklyQuota != nil {
                VStack(spacing: 8) {
                    if let q5 = metrics.fiveHourQuota {
                        QuotaPoolTelemetryRow(
                            title: "Phiên 5 Giờ (Burst Window)",
                            subtitle: "Hạn mức ngắn hạn tự hồi sau 5 giờ",
                            quota: q5,
                            accent: PulseTheme.emerald,
                            now: now
                        )
                    }

                    if let q7 = metrics.weeklyQuota {
                        QuotaPoolTelemetryRow(
                            title: "Giới Hạn Tuần (7-Day Cap)",
                            subtitle: "Tổng hạn mức sử dụng chu kỳ tuần",
                            quota: q7,
                            accent: PulseTheme.teal,
                            now: now
                        )
                    }
                }
            } else {
                OfflineQuotaNotice(message: metrics.statusMessage)
            }

            // Extra metadata (reset credits if available)
            if let rc = metrics.resetCreditsAvailable, rc > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.caption)
                        .foregroundStyle(PulseTheme.emerald)
                    Text("Lượt reset hạn mức dự phòng sẵn có: \(rc)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PulseTheme.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Real Codex SQLite Token Matrix
            TokenStatsMatrix(
                tokens5H: metrics.formattedTokensLast5Hours,
                tokensToday: metrics.formattedTokensToday,
                tokens7D: metrics.formattedTokensLast7Days,
                turnsToday: 0,
                sessionsToday: metrics.activeSessionsToday,
                accent: PulseTheme.emerald
            )
        }
        .telemetryCard(accent: PulseTheme.emerald, cornerRadius: 12, padding: 13)
    }
}

// MARK: - Shared Precision Subcomponents
private struct SourceStateBadge: View {
    let state: AIQuotaSourceState
    let syncTime: Date

    private var color: Color {
        switch state {
        case .live: return PulseTheme.emerald
        case .cached: return PulseTheme.amber
        case .offline: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                LivePulseDot(color: color, isLive: state == .live)
                Text(state.badgeLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())

            Text(syncTime, style: .time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
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
        if quota.usedPercent >= 90 { return PulseTheme.crimson }
        if quota.usedPercent >= 70 { return PulseTheme.amber }
        return accent
    }

    var body: some View {
        HStack(spacing: 11) {
            QuotaRingView(
                remainingPercent: quota.remainingPercent,
                color: healthColor,
                size: 44,
                lineWidth: 4.2
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Còn \(quota.formattedRemainingPercent)")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(healthColor)
                        Text("Đã dùng \(quota.formattedUsedPercent)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                TickProgressBar(
                    ratio: quota.remainingPercent / 100.0,
                    color: healthColor,
                    height: 6,
                    showTicks: true
                )

                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 9.5))
                        .foregroundStyle(healthColor)
                    Text("Làm mới sau: \(quota.formattedResetCountdown(relativeTo: now))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let resetAt = quota.resetAt {
                        Text(resetAt, style: .time)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(healthColor.opacity(0.18), lineWidth: 0.7)
        )
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
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6.5)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct OfflineQuotaNotice: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13))
                .foregroundStyle(PulseTheme.amber)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(PulseTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
