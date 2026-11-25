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
    @Environment(\.colorScheme) private var systemScheme
    @State private var hoveredTab: AppTab?
    @Namespace private var tabIndicatorNS

    private var effectiveScheme: ColorScheme {
        vm.appearanceMode == .darkCockpit ? .dark : systemScheme
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.45)

            customTabBar
                .padding(.horizontal, 14)
                .padding(.top, 9)
                .padding(.bottom, 7)

            if let notice = vm.actionNotice {
                actionNoticeBanner(notice)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 7)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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

            Divider().opacity(0.45)
            footerBar
        }
        .frame(width: 560, height: 680)
        .background(PulseTheme.canvasBackground(for: effectiveScheme))
        .preferredColorScheme(vm.appearanceMode == .darkCockpit ? .dark : nil)
        .animation(.easeInOut(duration: 0.18), value: vm.actionNotice)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            vm.setPopoverVisible(true)
        }
        .onDisappear {
            vm.setPopoverVisible(false)
        }
    }

    // MARK: - Smart Action Toast
    private func actionNoticeBanner(_ message: String) -> some View {
        let accent: Color
        let icon: String
        switch vm.actionNoticeKind {
        case .success:
            accent = PulseTheme.emerald
            icon = "checkmark.circle.fill"
        case .info:
            accent = PulseTheme.cyan
            icon = "info.circle.fill"
        case .warning:
            accent = PulseTheme.amber
            icon = "exclamationmark.triangle.fill"
        case .error:
            accent = PulseTheme.crimson
            icon = "xmark.octagon.fill"
        }

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                vm.dismissNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(accent.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(accent.opacity(0.32), lineWidth: 0.9)
        )
    }

    // MARK: - Precision Cockpit Header
    private var headerBar: some View {
        HStack(spacing: 10) {
            ArcHealthGauge(
                score: vm.healthReport?.score ?? 100,
                color: statusColor,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("MacPulse")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("v2.0")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(PulseTheme.cyan.opacity(0.16), in: Capsule())
                        .foregroundStyle(PulseTheme.cyan)
                    Text(vm.hardwareSpecs.compactBadge)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .lineLimit(1)
                }

                HStack(spacing: 7) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(vm.healthReport?.statusLabel ?? "Đang phân tích...")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(statusColor)
                    }

                    if let snap = vm.snapshot {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 3) {
                            Image(systemName: thermalIcon(snap.thermalLevel))
                                .font(.system(size: 9))
                            Text(snap.thermalLevel.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(thermalColor(snap.thermalLevel))

                        if snap.uptimeSeconds > 60 {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("Up \(snap.formattedUptime)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Appearance quick toggle (Dark Cockpit / System)
            Button {
                vm.toggleAppearanceMode()
            } label: {
                Image(systemName: vm.appearanceMode == .darkCockpit ? "moon.stars.fill" : "circle.lefthalf.filled")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(vm.appearanceMode == .darkCockpit ? PulseTheme.cyan : .secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.07), in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help(vm.appearanceMode == .darkCockpit ? "Giao diện Dark Cockpit (bấm để theo hệ thống macOS)" : "Giao diện theo macOS (bấm để bật Dark Cockpit)")

            // Quick VI / EN toggle capsule
            Button {
                vm.toggleVietnameseEnabled()
            } label: {
                let activeColor = vm.imeSettings.isEnabled ? PulseTheme.cyan : Color.gray
                HStack(spacing: 4) {
                    Circle()
                        .fill(activeColor)
                        .frame(width: 6.5, height: 6.5)
                        .shadow(color: vm.imeSettings.isEnabled ? activeColor.opacity(0.7) : .clear, radius: 2.5)
                    Text(vm.imeSettings.isEnabled ? "VI" : "EN")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text(vm.imeSettings.inputMethod == .vni ? "VNI" : (vm.imeSettings.inputMethod == .telex ? "TLX" : "T+V"))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .opacity(0.8)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(activeColor.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(activeColor.opacity(0.38), lineWidth: 0.9))
                .foregroundStyle(vm.imeSettings.isEnabled ? PulseTheme.cyan : .secondary)
            }
            .buttonStyle(.plain)
            .help("Bấm hoặc nhấn \(vm.imeSettings.hotkey.displayName) để chuyển Việt / Anh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Sliding Segmented Navigation Bar
    private var customTabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = vm.selectedTab == tab
                let showDot = dotColor(for: tab)
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        vm.selectedTab = tab
                        if tab == .cleaner {
                            vm.cleanerFocus = .all
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: iconForTab(tab))
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                        if let dotColor = showDot {
                            Circle()
                                .fill(dotColor)
                                .frame(width: 5.5, height: 5.5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6.5)
                    .padding(.horizontal, 4)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [PulseTheme.cyan.opacity(0.88), PulseTheme.cobalt.opacity(0.92)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: PulseTheme.cobalt.opacity(0.32), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "activeTabPill", in: tabIndicatorNS)
                        } else if hoveredTab == tab {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        }
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab_\(tab.rawValue)")
                .accessibilityLabel(tab.rawValue)
                .onHover { hovering in
                    hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
                }
            }
        }
        .padding(3.5)
        .background(PulseTheme.cardFill(for: effectiveScheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(PulseTheme.borderColor(for: effectiveScheme), lineWidth: 0.8)
        )
    }

    private func dotColor(for tab: AppTab) -> Color? {
        switch tab {
        case .vietnamese:
            return (!vm.isAccessibilityTrusted || !vm.conflictingApps.isEmpty) ? PulseTheme.amber : nil
        case .cleaner:
            return (vm.orphanAutomationGroup != nil || !vm.stuckChromeRenderers.isEmpty) ? PulseTheme.amber : nil
        case .aiPulse:
            if let gpt = vm.aiSnapshot?.chatGPT, gpt.limitReached { return PulseTheme.crimson }
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

    // MARK: - Footer Control Strip
    private var footerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(PulseTheme.emerald)
                    .frame(width: 5.5, height: 5.5)
                Text(vm.lastUpdated, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 12)

            // Launch at Login compact toggle
            Button {
                vm.setLaunchAtLogin(!vm.launchAtLoginEnabled)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: vm.launchAtLoginEnabled ? "bolt.circle.fill" : "bolt.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(vm.launchAtLoginEnabled ? PulseTheme.emerald : .secondary)
                    Text("Tự mở cùng macOS")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(vm.launchAtLoginEnabled ? .primary : .secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    (vm.launchAtLoginEnabled ? PulseTheme.emerald.opacity(0.12) : Color.primary.opacity(0.05)),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .help("Bật/tắt tự khởi động MacPulse khi đăng nhập macOS")

            // Menu Bar display mode cycler
            Button {
                vm.cycleMenuBarDisplayMode()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 10))
                    Text(vm.menuBarDisplayMode.rawValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Đổi kiểu hiển thị trên thanh Menu Bar (CPU•RAM / CPU•AI / Siêu gọn)")

            Spacer()

            Button {
                vm.refreshNow(includeProcesses: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .controlSize(.small)
            .help("Làm mới dữ liệu ngay")

            Button("Thoát") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch vm.healthReport?.severity ?? .ok {
        case .ok: return PulseTheme.emerald
        case .warning: return PulseTheme.amber
        case .critical: return PulseTheme.crimson
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
        case .nominal: return .secondary
        case .fair: return PulseTheme.amber
        case .serious, .critical: return PulseTheme.crimson
        }
    }
}
