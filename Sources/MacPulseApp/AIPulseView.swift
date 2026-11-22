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
                summaryBanner
                providersList
                efficiencyNotice
            }
            .padding(14)
        }
        .onAppear {
            if vm.aiSnapshot == nil {
                vm.refreshAIQuota()
            }
        }
    }

    // MARK: - Top Summary Banner
    private var summaryBanner: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("AI Pulse • Token & Quota")
                            .font(.system(size: 14, weight: .bold))
                        if vm.isScanningAI {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text("Theo dõi token tiêu thụ và trạng thái tài khoản AI trên máy")
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
                        Text("Cập nhật")
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

            Divider()

            if let snap = vm.aiSnapshot {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tổng Token Hôm Nay")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(snap.formattedGrandTotal)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Divider()
                        .frame(height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Công Cụ Sẵn Sàng")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(snap.activeProvidersCount) / \(snap.providers.count) nền tảng")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    if let agy = snap.providers.first(where: { $0.providerType == .antigravity }), agy.isDetected, let cost = agy.estimatedCostTodayUSD {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Ước Tính Chi Phí")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "~$%.3f", cost))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                    }
                }
            } else {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Đang đọc dữ liệu token...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.purple.opacity(0.04))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Providers List
    private var providersList: some View {
        VStack(spacing: 10) {
            if let snap = vm.aiSnapshot {
                ForEach(snap.providers) { provider in
                    providerCard(provider)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Đang kiểm tra các tài khoản AI trên máy...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
    }

    private func providerCard(_ provider: AIProviderMetrics) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(providerColor(provider.providerType).opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: provider.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(providerColor(provider.providerType))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 13, weight: .semibold))
                        if provider.isDetected {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text(provider.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let model = provider.activeModel {
                    Text(model)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .foregroundStyle(.primary)
                }
            }

            if provider.isDetected && provider.totalTokensToday > 0 {
                Divider()

                HStack(spacing: 12) {
                    tokenMiniStat(label: "Hôm nay", value: provider.formattedTokensToday, color: .purple)
                    tokenMiniStat(label: "Prompt Input", value: provider.formattedInputTokens, color: .blue)
                    tokenMiniStat(label: "Output", value: provider.formattedOutputTokens, color: .green)
                    tokenMiniStat(label: "Cache Read", value: provider.formattedCacheTokens, color: .orange)
                    Spacer()
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    provider.isDetected
                    ? providerColor(provider.providerType).opacity(0.25)
                    : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    private func tokenMiniStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func providerColor(_ type: AIProviderType) -> Color {
        switch type {
        case .antigravity: return Color.cyan
        case .openaiCodex: return Color.green
        case .commandcode: return Color.indigo
        case .claude: return Color.orange
        }
    }

    // MARK: - Efficiency Notice
    private var efficiencyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("Đo lường an toàn: MacPulse chỉ đọc trực tiếp log cục bộ với quyền Read-Only. Không bao giờ gửi dữ liệu ra ngoài, không tiêu tốn băng thông mạng và 0% ảnh hưởng đến tốc độ bàn phím.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue.opacity(0.12), lineWidth: 1)
        )
    }
}
