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
        case .safeNow: return PulseTheme.emerald
        case .cautionSaveFirst: return PulseTheme.amber
        case .remoteKeepAlive: return PulseTheme.crimson
        case .systemProtected: return .secondary
        }
    }

    private var cpuIntensity: Double {
        min(1.0, group.totalCPUPercent / 100.0)
    }

    private var ramIntensity: Double {
        let totalRAM = max(1.0, Double(vm.hardwareSpecs.totalRAMBytes))
        return min(1.0, Double(group.totalRSSBytes) / (totalRAM * 0.35))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.guidance.safetyLevel.badgeLabel)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(safetyColor.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(safetyColor.opacity(0.30), lineWidth: 0.6))
                    .foregroundStyle(safetyColor)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(group.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if group.processCount > 1 {
                            Text("×\(group.processCount)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if highlightRAM {
                        Text(String(format: "CPU %.0f%%", group.totalCPUPercent))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                if !highlightRAM {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f%%", group.totalCPUPercent))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(cpuColor)
                        microLoadBar(ratio: cpuIntensity, color: cpuColor)
                    }
                    .frame(width: 44, alignment: .trailing)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.bytes(group.totalRSSBytes))
                        .font(.system(size: 11, weight: highlightRAM ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(highlightRAM ? .primary : .secondary)
                    microLoadBar(ratio: ramIntensity, color: highlightRAM ? PulseTheme.cyan : PulseTheme.cobalt.opacity(0.8))
                }
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
                        .font(.system(size: 13.5))
                        .foregroundStyle(showGuidanceCard ? PulseTheme.cyan : .secondary)
                        .frame(width: 20, height: 20)
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
        .telemetryCard(
            accent: group.isOrphanAutomation ? PulseTheme.amber : (showGuidanceCard ? PulseTheme.cyan : nil),
            cornerRadius: 9,
            padding: 8
        )
    }

    private func microLoadBar(ratio: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.08))
            Capsule()
                .fill(color)
                .frame(width: max(2, 34 * CGFloat(max(0, min(1, ratio)))))
        }
        .frame(width: 34, height: 2.5)
    }

    @ViewBuilder
    private var actionTrailingControl: some View {
        if group.isOrphanAutomation {
            Button {
                vm.requestCloseProcess(group)
            } label: {
                Text("Dừng & Reset")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(PulseTheme.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(PulseTheme.amber.opacity(0.4), lineWidth: 0.7))
                    .foregroundStyle(PulseTheme.amber)
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
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 3.5)
                        .background(PulseTheme.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(PulseTheme.cyan)
                }
                .buttonStyle(.plain)

                Button {
                    vm.pendingTerminationGroup = group
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(PulseTheme.crimson.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(PulseTheme.crimson)
                }
                .buttonStyle(.plain)
                .help("Đóng cả ứng dụng \(group.displayName) (sẽ hỏi xác nhận)")
            }
        } else if group.guidance.safetyLevel == .cautionSaveFirst {
            Button {
                vm.requestCloseProcess(group)
            } label: {
                Text("Đóng")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(PulseTheme.crimson.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(PulseTheme.crimson)
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
        if group.totalCPUPercent >= 50 { return PulseTheme.crimson }
        if group.totalCPUPercent >= 18 { return PulseTheme.amber }
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
                Text("Trạng thái:")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PulseTheme.cyan)
                Text(guidance.currentActivityHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 5) {
                Text("Tác động:")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PulseTheme.amber)
                Text(guidance.impactIfClosed)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 5) {
                Text("Khuyến nghị:")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PulseTheme.emerald)
                Text(guidance.recommendedHowTo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(PulseTheme.cyan.opacity(0.20), lineWidth: 0.6))
    }
}

struct InlineConfirmTerminationCard: View {
    let group: ProcessGroupSummary
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(PulseTheme.amber)
                Text("Xác nhận đóng \(group.displayName)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("~\(Formatters.bytes(group.totalRSSBytes)) RAM")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(PulseTheme.cyan)
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
                    .tint(PulseTheme.cyan)
                    .controlSize(.small)
                }

                Button("Đóng nhẹ (Cmd+Q)") {
                    vm.confirmTermination(for: group, force: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.amber)
                .controlSize(.small)

                if group.canForceTerminate {
                    Button("Ép tắt (khi treo)") {
                        vm.confirmTermination(for: group, force: true)
                    }
                    .buttonStyle(.bordered)
                    .tint(PulseTheme.crimson)
                    .controlSize(.small)
                }

                Spacer()

                Button("Huỷ") {
                    vm.pendingTerminationGroup = nil
                }
                .controlSize(.small)
            }
        }
        .telemetryCard(accent: PulseTheme.amber, cornerRadius: 11, padding: 11)
    }
}

struct BrowserTabsInspectorCard: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "macwindow.on.rectangle")
                    .foregroundStyle(PulseTheme.cyan)
                Text("Quản lý Tab Đa Trình Duyệt (\(vm.openBrowserTabs.count) tab)")
                    .font(.system(size: 12.5, weight: .bold))
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
                        .foregroundStyle(PulseTheme.amber)
                }
            }

            if !vm.duplicateTabs.isEmpty {
                HStack {
                    Image(systemName: "square.on.square.dashed")
                        .font(.caption)
                        .foregroundStyle(PulseTheme.amber)
                    Text("Phát hiện \(vm.duplicateTabs.count) nhóm URL mở trùng lặp")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PulseTheme.amber)
                    Spacer()
                    Button("Đóng tất cả bản trùng") {
                        vm.closeDuplicateExtras()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.amber)
                    .controlSize(.mini)
                }
                .padding(7)
                .background(PulseTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            }

            if !vm.openBrowserTabs.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Lọc theo tiêu đề, URL hoặc tên trình duyệt...", text: $vm.tabSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !vm.tabSearchQuery.isEmpty {
                        Button {
                            vm.tabSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }

            let matching = vm.filteredBrowserTabs
            let shown = vm.showAllTabs ? matching : Array(matching.prefix(12))

            if matching.isEmpty && !vm.isScanningTabs {
                Text(vm.openBrowserTabs.isEmpty
                     ? "Không đọc được tab nào hoặc trình duyệt (Chrome, Brave, Edge, Arc, Safari) chưa mở tab."
                     : "Không có tab nào khớp từ khoá tìm kiếm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(shown) { tab in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tab.title.isEmpty ? tab.url : tab.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text("\(tab.browser) • \(tab.url)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Đóng") {
                                vm.closeSingleBrowserTab(tab)
                            }
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if matching.count > 12 {
                        Button {
                            vm.showAllTabs.toggle()
                        } label: {
                            Text(vm.showAllTabs ? "Thu gọn" : "Xem toàn bộ \(matching.count) tab")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(PulseTheme.cyan)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .telemetryCard(accent: PulseTheme.cyan, cornerRadius: 11, padding: 11)
    }
}
