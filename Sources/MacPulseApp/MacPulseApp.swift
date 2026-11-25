import AppKit
import SwiftUI
import MacPulseCore

@main
struct MacPulseApp: App {
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView(vm: vm)
        } label: {
            MenuBarLabelView(
                symbolName: vm.menuBarSymbolName,
                compactLabel: vm.menuBarCompactLabel
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabelView: View {
    let symbolName: String
    let compactLabel: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
            if !compactLabel.isEmpty {
                Text(compactLabel)
                    .monospacedDigit()
            }
        }
    }
}

private struct PopoverRootView: View {
    @ObservedObject var vm: AppViewModel
    @State private var hoveredTab: AppTab?
    @Namespace private var tabIndicatorNS

    private var isQuantumViolet: Bool {
        vm.appearanceMode == .system
    }

    private var primaryAccent: Color {
        HudTheme.primaryAccent(quantumMode: isQuantumViolet)
    }

    var body: some View {
        ZStack {
            SciFiBackgroundCanvas(accent: primaryAccent).equatable()

            VStack(spacing: 0) {
                headerBar
                neonHairline

                commandDockBar
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 7)

                if let notice = vm.actionNotice {
                    actionNoticeBanner(notice)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 7)
                }

                Group {
                    switch vm.selectedTab {
                    case .overview: DashboardView(vm: vm)
                    case .aiPulse: AIPulseView(vm: vm)
                    case .cleaner: CleanerView(vm: vm)
                    case .vietnamese: VietnameseView(vm: vm)
                    case .benchmark: BenchmarkView(vm: vm)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                neonHairline
                footerBar
            }
        }
        .frame(width: 575, height: 690)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .foregroundStyle(HudTheme.textPrimary)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            vm.setPopoverVisible(true)
        }
        .onDisappear {
            vm.setPopoverVisible(false)
        }
    }

    private var neonHairline: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, primaryAccent.opacity(0.45), HudTheme.violet.opacity(0.28), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    // MARK: - Smart Action Toast
    private func actionNoticeBanner(_ message: String) -> some View {
        let accent: Color
        let icon: String
        switch vm.actionNoticeKind {
        case .success:
            accent = HudTheme.emerald
            icon = "checkmark.seal.fill"
        case .info:
            accent = HudTheme.cyan
            icon = "info.circle.fill"
        case .warning:
            accent = HudTheme.amber
            icon = "exclamationmark.triangle.fill"
        case .error:
            accent = HudTheme.crimson
            icon = "xmark.octagon.fill"
        }

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .font(.system(size: 12, weight: .bold))
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HudTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                vm.dismissNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(HudTheme.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            ChamferedRect(cut: 6, cornerRadius: 3)
                .fill(HudTheme.cardBgHi)
                .overlay(ChamferedRect(cut: 6, cornerRadius: 3).fill(accent.opacity(0.14)))
        )
        .overlay(
            ChamferedRect(cut: 6, cornerRadius: 3)
                .strokeBorder(accent.opacity(0.55), lineWidth: 0.9)
        )
    }

    // MARK: - Sci-Fi Mission Control Header
    private var headerBar: some View {
        HStack(spacing: 11) {
            ArcHealthGauge(
                score: vm.healthReport?.score ?? 100,
                color: statusColor,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("MACPULSE")
                        .font(.system(size: 14.5, weight: .black, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(HudTheme.textPrimary)

                    Text("v2.0")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(primaryAccent.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(primaryAccent.opacity(0.48), lineWidth: 0.7))
                        .foregroundStyle(primaryAccent)

                    Text(vm.hardwareSpecs.compactBadge)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 1.5)
                        .background(HudTheme.insetBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(HudTheme.textMuted.opacity(0.32), lineWidth: 0.7))
                        .lineLimit(1)
                }

                HStack(spacing: 7) {
                    HStack(spacing: 4) {
                        LivePulseDot(color: statusColor, isLive: true)
                        Text(vm.healthReport?.statusLabel ?? "Đang phân tích...")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }

                    if let snap = vm.snapshot {
                        Text("│")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(HudTheme.textMuted)
                        HStack(spacing: 3) {
                            Image(systemName: thermalIcon(snap.thermalLevel))
                                .font(.system(size: 9.5))
                            Text(snap.thermalLevel.label)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(thermalColor(snap.thermalLevel))

                        if snap.uptimeSeconds > 60 {
                            Text("│")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(HudTheme.textMuted)
                            Text("UP \(snap.formattedUptime)")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(HudTheme.textSecondary)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // HUD Accent Switcher (Cyber Cyan <-> Quantum Violet)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    vm.toggleAppearanceMode()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(HudTheme.cardBgHi)
                        .overlay(Circle().strokeBorder(primaryAccent.opacity(0.5), lineWidth: 0.9))
                        .frame(width: 28, height: 28)
                    Image(systemName: isQuantumViolet ? "sparkles" : "atom")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(primaryAccent)
                }
            }
            .buttonStyle(.plain)
            .help(isQuantumViolet ? "Tông màu: Quantum Violet (bấm để đổi sang Cyber Cyan)" : "Tông màu: Cyber Cyan (bấm để đổi sang Quantum Violet)")

            // Neon VI / EN Hardware Pill
            Button {
                vm.toggleVietnameseEnabled()
            } label: {
                let activeColor = vm.imeSettings.isEnabled ? HudTheme.cyan : HudTheme.textMuted
                HStack(spacing: 4.5) {
                    Circle()
                        .fill(activeColor)
                        .frame(width: 6.5, height: 6.5)
                    Text(vm.imeSettings.isEnabled ? "VI" : "EN")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text(vm.imeSettings.inputMethod == .vni ? "VNI" : (vm.imeSettings.inputMethod == .telex ? "TLX" : "T+V"))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(activeColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(
                    ChamferedRect(cut: 6, cornerRadius: 3)
                        .fill(vm.imeSettings.isEnabled ? activeColor.opacity(0.18) : HudTheme.insetBg)
                )
                .overlay(
                    ChamferedRect(cut: 6, cornerRadius: 3)
                        .strokeBorder(activeColor.opacity(vm.imeSettings.isEnabled ? 0.78 : 0.35), lineWidth: 0.95)
                )
            }
            .buttonStyle(.plain)
            .help("Bấm hoặc nhấn \(vm.imeSettings.hotkey.displayName) để chuyển Việt / Anh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Sci-Fi Command Navigation Dock
    private var commandDockBar: some View {
        HStack(spacing: 5) {
            ForEach(AppTab.allCases) { tab in
                commandDockButton(for: tab)
            }
        }
        .padding(4)
        .background(
            ChamferedRect(cut: 8, cornerRadius: 4)
                .fill(HudTheme.insetBg.opacity(0.95))
        )
        .overlay(
            ChamferedRect(cut: 8, cornerRadius: 4)
                .strokeBorder(primaryAccent.opacity(0.24), lineWidth: 0.85)
        )
    }

    private func commandDockButton(for tab: AppTab) -> some View {
        let isSelected = vm.selectedTab == tab
        let alertDot = dotColor(for: tab)
        return Button {
            NSApp.activate(ignoringOtherApps: true)
            vm.selectedTab = tab
            if tab == .cleaner && vm.isReplaydStuck {
                vm.cleanerFocus = .chrome
            }
        } label: {
            HStack(spacing: 4.5) {
                Image(systemName: iconForTab(tab))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(isSelected ? primaryAccent : HudTheme.textSecondary)
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? HudTheme.textPrimary : HudTheme.textSecondary)
                    .lineLimit(1)
                if let dot = alertDot {
                    Circle()
                        .fill(dot)
                        .frame(width: 5.5, height: 5.5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background {
                if isSelected {
                    ChamferedRect(cut: 6, cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [primaryAccent.opacity(0.26), HudTheme.cobalt.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            ChamferedRect(cut: 6, cornerRadius: 3)
                                .strokeBorder(primaryAccent.opacity(0.75), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "hudActiveTab", in: tabIndicatorNS)
                } else if hoveredTab == tab {
                    ChamferedRect(cut: 6, cornerRadius: 3)
                        .fill(HudTheme.cardBgHi.opacity(0.85))
                        .overlay(
                            ChamferedRect(cut: 6, cornerRadius: 3)
                                .strokeBorder(primaryAccent.opacity(0.25), lineWidth: 0.7)
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab_\(tab.rawValue)")
        .accessibilityLabel(tab.rawValue)
        .onHover { hovering in
            hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
        }
    }

    private func dotColor(for tab: AppTab) -> Color? {
        switch tab {
        case .vietnamese:
            return (!vm.isAccessibilityTrusted || !vm.conflictingApps.isEmpty) ? HudTheme.amber : nil
        case .cleaner:
            if vm.isReplaydStuck { return HudTheme.crimson }
            return (vm.orphanAutomationGroup != nil || !vm.stuckChromeRenderers.isEmpty || vm.chromeGPUTotalCPU >= 15.0) ? HudTheme.amber : nil
        case .aiPulse:
            if !vm.openCodeRunningSessions.isEmpty { return HudTheme.cyan }
            if vm.openCodeUnreadCompletions > 0 { return HudTheme.emerald }
            if let gpt = vm.aiSnapshot?.chatGPT, gpt.limitReached { return HudTheme.crimson }
            return nil
        default:
            return nil
        }
    }

    private func iconForTab(_ tab: AppTab) -> String {
        switch tab {
        case .overview: return "waveform.path.ecg"
        case .aiPulse: return "cpu.fill"
        case .cleaner: return "sparkles"
        case .vietnamese: return "keyboard"
        case .benchmark: return "speedometer"
        }
    }

    // MARK: - Sci-Fi Footer Command Bar (100% Explicit High-Contrast Controls)
    private var footerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(HudTheme.emerald)
                    .frame(width: 5.5, height: 5.5)
                Text(vm.lastUpdated, style: .time)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
            }

            Text("│")
                .font(.system(size: 10))
                .foregroundStyle(HudTheme.textMuted.opacity(0.5))

            // Launch at Login toggle pill
            Button {
                vm.setLaunchAtLogin(!vm.launchAtLoginEnabled)
            } label: {
                let c = vm.launchAtLoginEnabled ? HudTheme.emerald : HudTheme.textSecondary
                HStack(spacing: 4) {
                    Image(systemName: vm.launchAtLoginEnabled ? "bolt.circle.fill" : "bolt.circle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(c)
                    Text("Tự mở cùng macOS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(vm.launchAtLoginEnabled ? HudTheme.textPrimary : HudTheme.textSecondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    (vm.launchAtLoginEnabled ? HudTheme.emerald.opacity(0.16) : HudTheme.cardBg),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(c.opacity(0.38), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .help("Bật/tắt tự khởi động MacPulse cùng macOS")

            // Menu Bar display mode cycler
            Button {
                vm.cycleMenuBarDisplayMode()
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 9.5))
                        .foregroundStyle(primaryAccent)
                    Text(vm.menuBarDisplayMode.rawValue)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(HudTheme.cardBg, in: Capsule())
                .overlay(Capsule().strokeBorder(primaryAccent.opacity(0.28), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .help("Đổi kiểu hiển thị trên thanh Menu Bar (CPU•RAM / CPU•AI / Gọn)")

            // Autopilot Auto-Optimize Status Pill
            Button {
                vm.cleanerFocus = .autopilot
                vm.selectedTab = .cleaner
            } label: {
                let isOn = vm.autoOptimizeConfig.isEnabled
                let pillColor = vm.isAutoOptimizing ? HudTheme.cyan : (isOn ? HudTheme.emerald : HudTheme.textMuted)
                HStack(spacing: 3.5) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(pillColor)
                    Text(vm.isAutoOptimizing ? "OPT" : "AUTO")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundStyle(isOn ? HudTheme.textPrimary : HudTheme.textMuted)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background((isOn ? pillColor.opacity(0.16) : HudTheme.cardBg), in: Capsule())
                .overlay(Capsule().strokeBorder(pillColor.opacity(isOn ? 0.45 : 0.25), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .help(vm.autoOptimizeConfig.isEnabled
                  ? "Autopilot Tự động Tối ưu đang BẬT (Đã dọn: \(Formatters.bytes(vm.autoOptimizeLifetimeFreedBytes))) — bấm để cấu hình"
                  : "Autopilot Tự động Tối ưu đang TẮT — bấm để mở cấu hình")

            Spacer()

            HudButton(title: "Quét", icon: "arrow.clockwise", color: primaryAccent, filled: false, compact: true) {
                vm.refreshNow(includeProcesses: true)
            }

            HudButton(title: "Thoát", icon: "power", color: HudTheme.crimson, filled: false, compact: true) {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(HudTheme.bgDeep.opacity(0.85))
    }

    private var statusColor: Color {
        switch vm.healthReport?.severity ?? .ok {
        case .ok: return HudTheme.emerald
        case .warning: return HudTheme.amber
        case .critical: return HudTheme.crimson
        }
    }

    private func thermalIcon(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious, .critical: return "flame.fill"
        }
    }

    private func thermalColor(_ level: ThermalLevel) -> Color {
        switch level {
        case .nominal: return HudTheme.emerald
        case .fair: return HudTheme.amber
        case .serious, .critical: return HudTheme.crimson
        }
    }
}
