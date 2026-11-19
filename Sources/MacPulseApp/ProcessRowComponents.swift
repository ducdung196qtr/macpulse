import SwiftUI
import MacPulseCore

struct ProcessRowView: View {
    let group: ProcessGroupSummary
    @ObservedObject var vm: AppViewModel
    let highlightRAM: Bool
    @State private var isHoveringInfo = false

    private var isPinnedInfo: Bool {
        vm.inspectedGuidanceGroup?.id == group.id
    }

    private var showGuidanceCard: Bool {
        isHoveringInfo || isPinnedInfo
    }

    private var safetyColor: Color {
        switch group.guidance.safetyLevel {
        case .safeNow: return .green
        case .cautionSaveFirst: return .orange
        case .remoteKeepAlive: return .red
        case .systemProtected: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.guidance.safetyLevel.badgeLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(safetyColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(safetyColor)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(group.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if group.processCount > 1 {
                            Text("(\(group.processCount))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if highlightRAM {
                        Text(String(format: "CPU %.0f%%", group.totalCPUPercent))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                if !highlightRAM {
                    Text(String(format: "%.0f%%", group.totalCPUPercent))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(cpuColor)
                        .frame(width: 44, alignment: .trailing)
                }

                Text(Formatters.bytes(group.totalRSSBytes))
                    .font(.caption.monospacedDigit().weight(highlightRAM ? .semibold : .regular))
                    .foregroundStyle(highlightRAM ? .primary : .secondary)
                    .frame(width: 68, alignment: .trailing)

                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        if isPinnedInfo {
                            vm.inspectedGuidanceGroup = nil
                        } else {
                            vm.inspectedGuidanceGroup = group
                        }
                    }
                } label: {
                    Image(systemName: showGuidanceCard ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(showGuidanceCard ? Color.accentColor : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isHoveringInfo = hovering
                    }
                }
                .accessibilityIdentifier("info_\(group.id)")
                .help("\(group.guidance.whatIsIt)\n• Trạng thái: \(group.guidance.currentActivityHint)\n• Tắt có sao không: \(group.guidance.impactIfClosed)")

                actionTrailingControl
            }

            if showGuidanceCard {
                GuidanceDetailCard(guidance: group.guidance)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(showGuidanceCard ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionTrailingControl: some View {
        if group.isOrphanAutomation {
            Button {
                vm.requestCloseProcess(group)
            } label: {
                Text("Dọn")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        } else if group.actionKind == .inspectBrowserTabs {
            HStack(spacing: 4) {
                Button {
                    vm.scanBrowserTabs()
                    if vm.selectedTab != .overview && vm.selectedTab != .cleaner {
                        vm.selectedTab = .overview
                    }
                } label: {
                    Text("Soi tab")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Button {
                    vm.pendingTerminationGroup = group
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Đóng cả ứng dụng \(group.displayName) (sẽ hỏi xác nhận)")
            }
        } else if group.guidance.safetyLevel == .cautionSaveFirst {
            Button {
                vm.requestCloseProcess(group)
            } label: {
                Text("Đóng")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("close_\(group.id)")
            .help("Đóng \(group.displayName) (hỏi xác nhận Đóng nhẹ hoặc Ép tắt)")
        } else {
            Image(systemName: group.guidance.safetyLevel == .remoteKeepAlive ? "antenna.radiowaves.left.and.right" : "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .center)
                .help(group.guidance.impactIfClosed)
        }
    }

    private var cpuColor: Color {
        if group.totalCPUPercent >= 50 { return .red }
        if group.totalCPUPercent >= 18 { return .orange }
        return .primary
    }
}

struct GuidanceDetailCard: View {
    let guidance: ProcessGuidance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(guidance.whatIsIt)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(alignment: .top, spacing: 5) {
                Text("Đang làm gì:")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(guidance.currentActivityHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 5) {
                Text("Tắt có sao không:")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(guidance.impactIfClosed)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 5) {
                Text("Gợi ý:")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                Text(guidance.recommendedHowTo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct InlineConfirmTerminationCard: View {
    let group: ProcessGroupSummary
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Xác nhận đóng \(group.displayName)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("~\(Formatters.bytes(group.totalRSSBytes)) RAM")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.blue)
            }

            Text("Trạng thái: \(group.guidance.currentActivityHint)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Ảnh hưởng khi tắt: \(group.guidance.impactIfClosed)")
                .font(.caption)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                if group.actionKind == .inspectBrowserTabs {
                    Button("Soi từng tab (Khuyên dùng)") {
                        vm.pendingTerminationGroup = nil
                        vm.scanBrowserTabs()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Đóng nhẹ (Cmd+Q)") {
                    vm.confirmTermination(for: group, force: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)

                if group.canForceTerminate {
                    Button("Ép tắt (khi treo)") {
                        vm.confirmTermination(for: group, force: true)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }

                Spacer()

                Button("Huỷ") {
                    vm.pendingTerminationGroup = nil
                }
                .controlSize(.small)
            }
        }
        .padding(11)
        .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        )
    }
}

struct BrowserTabsInspectorCard: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "safari")
                    .foregroundStyle(.blue)
                Text("Quản lý Tab Chrome / Edge (\(vm.openBrowserTabs.count) tab)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(vm.isScanningTabs ? "Đang quét..." : "Quét lại") {
                    vm.scanBrowserTabs()
                }
                .controlSize(.mini)
                .disabled(vm.isScanningTabs)

                Button {
                    vm.showTabInspector = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if !vm.tabWarnings.isEmpty {
                ForEach(vm.tabWarnings, id: \.self) { w in
                    Text("Lưu ý quyền Automation: \(w)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if !vm.duplicateTabs.isEmpty {
                HStack {
                    Text("Phát hiện \(vm.duplicateTabs.count) nhóm URL mở trùng")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Đóng tất cả bản trùng") {
                        vm.closeDuplicateExtras()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.mini)
                }
            }

            if vm.openBrowserTabs.isEmpty && !vm.isScanningTabs {
                Text("Không đọc được tab nào hoặc trình duyệt chưa mở tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(vm.openBrowserTabs.prefix(12)) { tab in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tab.title.isEmpty ? tab.url : tab.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text("\(tab.browser) • \(tab.url)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Đóng tab") {
                                vm.closeSingleBrowserTab(tab)
                            }
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if vm.openBrowserTabs.count > 12 {
                        Text("Đang hiển thị 12/\(vm.openBrowserTabs.count) tab đầu tiên.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.28), lineWidth: 1)
        )
    }
}
