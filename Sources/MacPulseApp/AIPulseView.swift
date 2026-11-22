import SwiftUI
import MacPulseCore

public struct AIPulseView: View {
    @ObservedObject var vm: AppViewModel

    public init(vm: AppViewModel) {
        self.vm = vm
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerBanner
                if let snap = vm.aiSnapshot {
                    // Google Antigravity Card
                    if let agy = snap.antigravity {
                        QuotaProviderCard(
                            metrics: agy,
                            gradientColors: [Color.blue.opacity(0.85), Color.purple.opacity(0.85)],
                            accentColor: .blue
                        )
                    }

                    // ChatGPT Card
                    if let gpt = snap.chatGPT {
                        QuotaProviderCard(
                            metrics: gpt,
                            gradientColors: [Color(red: 0.06, green: 0.65, blue: 0.52), Color(red: 0.10, green: 0.50, blue: 0.45)],
                            accentColor: Color(red: 0.06, green: 0.65, blue: 0.52)
                        )
                    }
                } else {
                    loadingPlaceholder
                }

                efficiencyFootnote
            }
            .padding(14)
        }
        .onAppear {
            if vm.aiSnapshot == nil {
                vm.refreshAIQuota()
            }
        }
    }

    // MARK: - Header
    private var headerBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Hạn Mức AI (5 Giờ & Tuần)")
                        .font(.system(size: 14, weight: .bold))
                    if vm.isScanningAI {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text("Theo dõi quota phiên 5 tiếng và hạn mức tuần (Antigravity & ChatGPT)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                vm.refreshAIQuota()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(vm.isScanningAI ? 360 : 0))
                        .animation(vm.isScanningAI ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isScanningAI)
                    Text("Làm mới")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Loading State
    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Đang tải dữ liệu hạn mức...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Footnote
    private var efficiencyFootnote: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            Text("Đo trực tiếp từ daemon nội bộ và API chính thức. 0 KB chạy ngầm, không trễ phím gõ.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Quota Provider Card
private struct QuotaProviderCard: View {
    let metrics: AIProviderMetrics
    let gradientColors: [Color]
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: metrics.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(metrics.name)
                            .font(.system(size: 13, weight: .bold))
                        if let plan = metrics.planTier {
                            Text(plan)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.15))
                                .foregroundStyle(accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    if let acc = metrics.userAccount {
                        Text(acc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let model = metrics.activeModel {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Model:")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(model)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
            }

            Divider()

            // 5-Hour Window Section
            if let fiveH = metrics.fiveHourQuota {
                WindowQuotaRow(
                    title: "Phiên 5 Giờ (5-Hour Window)",
                    icon: "clock.arrow.circlepath",
                    quota: fiveH,
                    accentColor: accentColor
                )
            }

            // Weekly Window Section
            if let weekly = metrics.weeklyQuota {
                WindowQuotaRow(
                    title: "Giới Hạn Tuần (Weekly Window)",
                    icon: "calendar.badge.clock",
                    quota: weekly,
                    accentColor: accentColor
                )
            }

            // Bottom Mini Metrics (Tokens today & last 7 days)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Hôm nay:")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(metrics.formattedTokensToday)
                        .font(.system(size: 10, weight: .bold))
                }

                if metrics.tokensLast7Days > 0 {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("7 ngày qua:")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(metrics.formattedTokensLast7Days)
                            .font(.system(size: 10, weight: .bold))
                    }
                }

                Spacer()

                HStack(spacing: 3) {
                    Circle()
                        .fill(metrics.isDetected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(metrics.isDetected ? "Sẵn sàng" : "Chưa kết nối")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Window Quota Row
private struct WindowQuotaRow: View {
    let title: String
    let icon: String
    let quota: AIWindowQuota
    let accentColor: Color

    private var progressColor: Color {
        if quota.usedPercent >= 90.0 {
            return .red
        } else if quota.usedPercent >= 70.0 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Còn lại:")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(quota.formattedRemainingPercent)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(progressColor)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [progressColor.opacity(0.8), progressColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(quota.remainingPercent / 100.0))), height: 6)
                }
            }
            .frame(height: 6)

            // Sub info: Reset countdown & note
            HStack {
                if quota.resetAt != nil {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("Làm mới sau: \(quota.formattedResetCountdown)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else if let note = quota.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Đã dùng: \(quota.formattedUsedPercent)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }
}
