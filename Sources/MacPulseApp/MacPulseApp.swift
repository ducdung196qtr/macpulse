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
            Text(compactLabel)
                .monospacedDigit()
        }
    }
}

private struct PopoverRootView: View {
    @ObservedObject var vm: AppViewModel
    @State private var hoveredTab: AppTab?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            customTabBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            if let notice = vm.actionNotice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        vm.actionNotice = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            Group {
                switch vm.selectedTab {
                case .overview: DashboardView(vm: vm)
                case .vietnamese: VietnameseView(vm: vm)
                case .benchmark: BenchmarkView(vm: vm)
                case .cleaner: CleanerView(vm: vm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footerBar
        }
        .frame(width: 535, height: 650)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            vm.setPopoverVisible(true)
        }
        .onDisappear {
            vm.setPopoverVisible(false)
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = vm.selectedTab == tab
                let showDot = (tab == .vietnamese) && (!vm.isAccessibilityTrusted || !vm.conflictingApps.isEmpty)
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    withAnimation(.easeInOut(duration: 0.15)) {
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
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        if showDot {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isSelected
                                ? Color.accentColor
                                : (hoveredTab == tab ? Color.primary.opacity(0.06) : Color.clear)
                            )
                    )
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
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
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func iconForTab(_ tab: AppTab) -> String {
        switch tab {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .vietnamese: return "keyboard"
        case .benchmark: return "speedometer"
        case .cleaner: return "sparkles"
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("MacPulse")
                        .font(.system(size: 15, weight: .bold))
                    if !vm.hardwareModelName.isEmpty {
                        Text(vm.hardwareModelName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
                Text(vm.healthReport?.statusLabel ?? "Đang phân tích...")
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
            Spacer()

            Button {
                vm.toggleVietnameseEnabled()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(vm.imeSettings.isEnabled ? Color.blue : Color.gray)
                        .frame(width: 7, height: 7)
                    Text(vm.imeSettings.isEnabled ? "VI" : "EN")
                        .font(.system(size: 11, weight: .bold))
                    Text(vm.imeSettings.inputMethod == .vni ? "VNI" : (vm.imeSettings.inputMethod == .telex ? "Telex" : "T+V"))
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.85)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    (vm.imeSettings.isEnabled ? Color.blue : Color.gray).opacity(0.15),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            (vm.imeSettings.isEnabled ? Color.blue : Color.gray).opacity(0.3),
                            lineWidth: 0.8
                        )
                )
            }
            .buttonStyle(.plain)
            .help("Bấm hoặc nhấn \(vm.imeSettings.hotkey.displayName) để chuyển Việt / Anh")

            if let report = vm.healthReport {
                HStack(spacing: 4) {
                    Text("\(report.score)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                    Text("/100")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.7)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15), in: Capsule())
                .foregroundStyle(statusColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footerBar: some View {
        HStack {
            Text("Cập nhật \(vm.lastUpdated, style: .time)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Làm mới") { vm.refreshNow(includeProcesses: true) }
                .controlSize(.small)
            Button("Thoát") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch vm.healthReport?.severity ?? .ok {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
