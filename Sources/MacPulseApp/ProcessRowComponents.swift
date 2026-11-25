import SwiftUI
import MacPulseCore

struct ProcessRowView: View {
    let group: ProcessGroupSummary
    @ObservedObject var vm: AppViewModel
    let highlightRAM: Bool

    private var isPinnedInfo: Bool {
        vm.inspectedGuidanceGroup?.id == group.id
    }

    private var showGuidanceCard: Bool {
        isPinnedInfo
    }

    private var safetyColor: Color {
        switch group.guidance.safetyLevel {
        case .safeNow: return HudTheme.emerald
        case .cautionSaveFirst: return HudTheme.amber
        case .remoteKeepAlive: return HudTheme.crimson
        case .systemProtected: return HudTheme.textMuted
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
                Text(group.guidance.safetyLevel.badgeLabel.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(safetyColor.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(safetyColor.opacity(0.45), lineWidth: 0.6))
                    .foregroundStyle(safetyColor)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(group.displayName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(HudTheme.textPrimary)
                            .lineLimit(1)
                        if group.processCount > 1 {
                            Text("×\(group.processCount)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(HudTheme.cyan.opacity(0.8))
                        }
                    }
                    if highlightRAM {
                        Text(String(format: "CPU %.0f%%", group.totalCPUPercent))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(HudTheme.textSecondary)
                    }
                }

                Spacer(minLength: 4)

                if !highlightRAM {
                    VStack(alignment: .trailing, spacing: 2.5) {
                        Text(String(format: "%.0f%%", group.totalCPUPercent))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(cpuColor)
                        microLoadBar(ratio: cpuIntensity, color: cpuColor)
                    }
                    .frame(width: 44, alignment: .trailing)
                }

                VStack(alignment: .trailing, spacing: 2.5) {
                    Text(Formatters.bytes(group.totalRSSBytes))
                        .font(.system(size: 10.5, weight: highlightRAM ? .bold : .semibold, design: .monospaced))
                        .foregroundStyle(highlightRAM ? HudTheme.cyan : HudTheme.textSecondary)
                    microLoadBar(ratio: ramIntensity, color: highlightRAM ? HudTheme.cyan : HudTheme.cobalt)
                }
                .frame(width: 68, alignment: .trailing)

                Button {
                    if isPinnedInfo {
                        vm.inspectedGuidanceGroup = nil
                    } else {
                        vm.inspectedGuidanceGroup = group
                    }
                } label: {
                    Image(systemName: showGuidanceCard ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 13.5))
                        .foregroundStyle(showGuidanceCard ? HudTheme.cyan : HudTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("info_\(group.id)")
                .help("\(group.guidance.whatIsIt)\n• Trạng thái: \(group.guidance.currentActivityHint)\n• Tắt có sao không: \(group.guidance.impactIfClosed)")

                actionTrailingControl
            }

            if showGuidanceCard {
                GuidanceDetailCard(guidance: group.guidance)
            }
        }
        .hudCard(
            accent: group.isOrphanAutomation ? HudTheme.amber : (showGuidanceCard ? HudTheme.cyan : HudTheme.cyan.opacity(0.32)),
            chamfer: 6,
            padding: 8,
            showBrackets: group.isOrphanAutomation || showGuidanceCard
        )
    }

    private func microLoadBar(ratio: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(HudTheme.insetBg)
            Capsule()
                .fill(color)
                .frame(width: max(2, 34 * CGFloat(max(0, min(1, ratio)))))
        }
        .frame(width: 34, height: 2.8)
    }

    @ViewBuilder
    private var actionTrailingControl: some View {
        if group.isOrphanAutomation {
            HudButton(title: "Dừng & Reset", color: HudTheme.amber, filled: true, compact: true) {
                vm.requestCloseProcess(group)
            }
        } else if group.actionKind == .inspectBrowserTabs {
            HStack(spacing: 4) {
                HudButton(title: "Soi tab", color: HudTheme.cyan, filled: false, compact: true) {
                    vm.scanBrowserTabs()
                    if vm.selectedTab != .overview && vm.selectedTab != .cleaner {
                        vm.selectedTab = .overview
                    }
                }

                Button {
                    vm.pendingTerminationGroup = group
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(HudTheme.crimson.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(HudTheme.crimson.opacity(0.45), lineWidth: 0.7))
                        .foregroundStyle(HudTheme.crimson)
                }
                .buttonStyle(.plain)
                .help("Đóng cả ứng dụng \(group.displayName) (sẽ hỏi xác nhận)")
            }
        } else if group.guidance.safetyLevel == .cautionSaveFirst {
            HudButton(title: "Đóng", color: HudTheme.crimson, filled: false, compact: true) {
                vm.requestCloseProcess(group)
            }
            .accessibilityIdentifier("close_\(group.id)")
            .help("Đóng \(group.displayName) (hỏi xác nhận Đóng nhẹ hoặc Ép tắt)")
        } else {
            Image(systemName: group.guidance.safetyLevel == .remoteKeepAlive ? "antenna.radiowaves.left.and.right" : "lock.fill")
                .font(.caption2)
                .foregroundStyle(group.guidance.safetyLevel == .remoteKeepAlive ? HudTheme.crimson : HudTheme.textMuted)
                .frame(width: 44, alignment: .center)
                .help(group.guidance.impactIfClosed)
        }
    }

    private var cpuColor: Color {
        if group.totalCPUPercent >= 50 { return HudTheme.crimson }
        if group.totalCPUPercent >= 18 { return HudTheme.amber }
        return HudTheme.textPrimary
    }
}

struct GuidanceDetailCard: View {
    let guidance: ProcessGuidance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(guidance.whatIsIt)
                .font(.caption.weight(.bold))
                .foregroundStyle(HudTheme.textPrimary)
            HStack(alignment: .top, spacing: 5) {
                Text("TRẠNG THÁI:")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.cyan)
                Text(guidance.currentActivityHint)
                    .font(.caption2)
                    .foregroundStyle(HudTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 5) {
                Text("TÁC ĐỘNG:")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.amber)
                Text(guidance.impactIfClosed)
                    .font(.caption2)
                    .foregroundStyle(HudTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 5) {
                Text("KHUYẾN NGHỊ:")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.emerald)
                Text(guidance.recommendedHowTo)
                    .font(.caption2)
                    .foregroundStyle(HudTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.cyan.opacity(0.28), lineWidth: 0.7))
    }
}

struct InlineConfirmTerminationCard: View {
    let group: ProcessGroupSummary
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(HudTheme.amber)
                Text("Xác nhận đóng \(group.displayName)")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(HudTheme.textPrimary)
                Spacer()
                Text("~\(Formatters.bytes(group.totalRSSBytes)) RAM")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.cyan)
            }

            Text("Trạng thái: \(group.guidance.currentActivityHint)")
                .font(.caption2)
                .foregroundStyle(HudTheme.textSecondary)

            Text("Ảnh hưởng khi tắt: \(group.guidance.impactIfClosed)")
                .font(.caption2)
                .foregroundStyle(HudTheme.textPrimary)

            HStack(spacing: 7) {
                if group.actionKind == .inspectBrowserTabs {
                    HudButton(title: "Soi từng tab", icon: "macwindow", color: HudTheme.cyan, filled: true, compact: true) {
                        vm.pendingTerminationGroup = nil
                        vm.scanBrowserTabs()
                    }
                }

                HudButton(title: "Đóng nhẹ (Cmd+Q)", color: HudTheme.amber, filled: true, compact: true) {
                    vm.confirmTermination(for: group, force: false)
                }

                if group.canForceTerminate {
                    HudButton(title: "Ép tắt", color: HudTheme.crimson, filled: false, compact: true) {
                        vm.confirmTermination(for: group, force: true)
                    }
                }

                Spacer()

                HudButton(title: "Huỷ", color: HudTheme.textSecondary, filled: false, compact: true) {
                    vm.pendingTerminationGroup = nil
                }
            }
        }
        .hudCard(accent: HudTheme.amber, chamfer: 9, padding: 11, showBrackets: true)
    }
}

struct BrowserTabsInspectorCard: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "macwindow.on.rectangle")
                    .foregroundStyle(HudTheme.cyan)
                Text("TAB SCANNER (\(vm.openBrowserTabs.count) TAB)")
                    .font(.system(size: 11.5, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textPrimary)
                Spacer()
                HudButton(title: vm.isScanningTabs ? "Đang quét..." : "Quét lại", color: HudTheme.cyan, filled: false, compact: true, disabled: vm.isScanningTabs) {
                    vm.scanBrowserTabs()
                }
                Button {
                    vm.showTabInspector = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HudTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if !vm.tabWarnings.isEmpty {
                ForEach(vm.tabWarnings, id: \.self) { w in
                    Text("Lưu ý quyền Automation: \(w)")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.amber)
                }
            }

            if !vm.duplicateTabs.isEmpty {
                HStack {
                    Image(systemName: "square.on.square.dashed")
                        .font(.caption)
                        .foregroundStyle(HudTheme.amber)
                    Text("Phát hiện \(vm.duplicateTabs.count) nhóm URL mở trùng lặp")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HudTheme.amber)
                    Spacer()
                    HudButton(title: "Đóng bản trùng", color: HudTheme.amber, filled: true, compact: true) {
                        vm.closeDuplicateExtras()
                    }
                }
                .padding(7)
                .background(HudTheme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.amber.opacity(0.4), lineWidth: 0.7))
            }

            if !vm.openBrowserTabs.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.cyan)
                    TextField("Lọc theo tiêu đề, URL hoặc tên trình duyệt...", text: $vm.tabSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(HudTheme.textPrimary)
                    if !vm.tabSearchQuery.isEmpty {
                        Button {
                            vm.tabSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(HudTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.cyan.opacity(0.25), lineWidth: 0.7))
            }

            let matching = vm.filteredBrowserTabs
            let shown = vm.showAllTabs ? matching : Array(matching.prefix(12))

            if matching.isEmpty && !vm.isScanningTabs {
                Text(vm.openBrowserTabs.isEmpty
                     ? "Không đọc được tab nào hoặc trình duyệt (Chrome, Brave, Edge, Arc, Safari) chưa mở tab."
                     : "Không có tab nào khớp từ khoá tìm kiếm.")
                    .font(.caption)
                    .foregroundStyle(HudTheme.textSecondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(shown) { tab in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tab.title.isEmpty ? tab.url : tab.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HudTheme.textPrimary)
                                    .lineLimit(1)
                                Text("\(tab.browser) • \(tab.url)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(HudTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            HudButton(title: "Đóng", color: HudTheme.crimson, filled: false, compact: true) {
                                vm.closeSingleBrowserTab(tab)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.cyan.opacity(0.16), lineWidth: 0.6))
                    }
                    if matching.count > 12 {
                        Button {
                            vm.showAllTabs.toggle()
                        } label: {
                            Text(vm.showAllTabs ? "THU GỌN" : "XEM TOÀN BỘ \(matching.count) TAB")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(HudTheme.cyan)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .hudCard(accent: HudTheme.cyan, chamfer: 9, padding: 11, showBrackets: true)
    }
}
