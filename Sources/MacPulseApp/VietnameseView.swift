import SwiftUI
import MacPulseCore

struct VietnameseView: View {
    @ObservedObject var vm: AppViewModel
    @State private var newMacroKey: String = ""
    @State private var newMacroValue: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                engineStatusCockpit
                conflictBanner
                systemInputSourceBanner
                modeAndHotkeyCard
                vpsAndExcludedAppsCard
                optionsCard
                macroCard
                scratchpadCard
            }
            .padding(14)
        }
        .onAppear {
            vm.refreshIMEEnvironment()
        }
    }

    // MARK: - Engine Status Cockpit
    @ViewBuilder
    private var engineStatusCockpit: some View {
        let ready = vm.isAccessibilityTrusted && vm.tapRuntimeState == .running
        let accent: Color = ready ? HudTheme.emerald : HudTheme.amber

        HStack(alignment: .center, spacing: 10) {
            ZStack {
                ChamferedRect(cut: 6, cornerRadius: 3)
                    .fill(accent.opacity(0.20))
                    .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(accent.opacity(0.6), lineWidth: 0.8))
                    .frame(width: 34, height: 34)
                Image(systemName: ready ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.6), radius: 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("EVKEY NEURAL ENGINE")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text(ready ? "ONLINE" : "WAITING")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(accent.opacity(0.20), in: Capsule())
                        .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 0.6))
                        .foregroundStyle(accent)
                }
                Text(vm.imeStatusSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            if !vm.isAccessibilityTrusted {
                HudButton(title: "Cấp quyền", icon: "lock.open.fill", color: HudTheme.amber, filled: true, compact: true) {
                    vm.requestAccessibilityPermission()
                    vm.openAccessibilitySettings()
                }
            } else if vm.isFrontmostAppBypassed && !vm.frontmostAppName.isEmpty {
                Text("BYPASS: \(vm.frontmostAppName.uppercased())")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(HudTheme.cyan.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(HudTheme.cyan.opacity(0.45), lineWidth: 0.7))
                    .foregroundStyle(HudTheme.cyan)
            }
        }
        .hudCard(accent: accent, chamfer: 9, padding: 11, showBrackets: true)
    }

    @ViewBuilder
    private var conflictBanner: some View {
        if !vm.conflictingApps.isEmpty {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(HudTheme.crimson)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phát hiện bộ gõ khác đang chạy song song")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text("\(vm.conflictingApps.map(\.name).joined(separator: ", ")) đang hoạt động. Tắt để tránh gõ đúp dấu.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                }
                Spacer()
                HudButton(title: "Tắt ngay", color: HudTheme.crimson, filled: true, compact: true) {
                    vm.terminateConflictingInputApps()
                }
            }
            .hudCard(accent: HudTheme.crimson, chamfer: 8, padding: 10)
        }
    }

    @ViewBuilder
    private var systemInputSourceBanner: some View {
        if vm.isSystemVietnameseInputSourceActive {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "keyboard.badge.exclamationmark")
                    .font(.system(size: 14))
                    .foregroundStyle(HudTheme.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text("macOS đang bật nguồn gõ Tiếng Việt (\(vm.systemInputSourceID))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text("Chuyển macOS về ABC / U.S. để MacPulse bắt phím chính xác 100%.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                }
                Spacer()
                HudButton(title: "Chuyển ABC", color: HudTheme.cyan, filled: true, compact: true) {
                    vm.switchSystemInputSourceToABC()
                }
            }
            .hudCard(accent: HudTheme.cyan, chamfer: 8, padding: 10)
        }
    }

    // MARK: - Mode & Hotkey Matrix
    private var modeAndHotkeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HudToggleRow(
                title: "Bật gõ Tiếng Việt cấp hệ thống",
                subtitle: "CGEventTap thuần Swift • Pacing chống lỗi Chrome/Electron • 0 thư viện ngoài",
                isOn: Binding(
                    get: { vm.imeSettings.isEnabled },
                    set: { val in
                        if val != vm.imeSettings.isEnabled { vm.toggleVietnameseEnabled() }
                    }
                ),
                accent: HudTheme.cyan
            )

            Rectangle()
                .fill(HudTheme.cyan.opacity(0.22))
                .frame(height: 0.75)

            HStack {
                Text("KIỂU GÕ")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(VietnameseInputMethod.allCases) { method in
                        let selected = vm.imeSettings.inputMethod == method
                        Button {
                            vm.imeSettings.inputMethod = method
                        } label: {
                            Text(method.displayName)
                                .font(.system(size: 10.5, weight: selected ? .bold : .medium, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    ChamferedRect(cut: 5, cornerRadius: 2)
                                        .fill(selected ? HudTheme.cobalt.opacity(0.32) : HudTheme.insetBg)
                                )
                                .overlay(
                                    ChamferedRect(cut: 5, cornerRadius: 2)
                                        .strokeBorder(selected ? HudTheme.cyan.opacity(0.85) : HudTheme.textMuted.opacity(0.28), lineWidth: 0.85)
                                )
                                .foregroundStyle(selected ? HudTheme.textPrimary : HudTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PHÍM TẮT CHUYỂN VIỆT / ANH")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(VietnameseHotkey.allCases) { hk in
                        let selected = vm.imeSettings.hotkey == hk
                        Button {
                            vm.imeSettings.hotkey = hk
                        } label: {
                            HStack(spacing: 5) {
                                Text(hotkeySymbols(hk))
                                    .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                    .foregroundStyle(selected ? HudTheme.cyan : HudTheme.textMuted)
                                Text(hk.displayName)
                                    .font(.system(size: 10.5, weight: selected ? .bold : .medium))
                                    .foregroundStyle(selected ? HudTheme.textPrimary : HudTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                            .background(
                                ChamferedRect(cut: 5, cornerRadius: 2)
                                    .fill(selected ? HudTheme.cyan.opacity(0.20) : HudTheme.insetBg)
                            )
                            .overlay(
                                ChamferedRect(cut: 5, cornerRadius: 2)
                                    .strokeBorder(selected ? HudTheme.cyan.opacity(0.8) : HudTheme.textMuted.opacity(0.25), lineWidth: 0.85)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .hudCard(accent: HudTheme.cyan.opacity(0.55), chamfer: 9, padding: 11)
    }

    private func hotkeySymbols(_ hk: VietnameseHotkey) -> String {
        switch hk {
        case .ctrlShift: return "⌃⇧"
        case .cmdShift: return "⌘⇧"
        case .optionZ: return "⌥Z"
        case .ctrlSpace: return "⌃␣"
        case .capsLock: return "⇪"
        }
    }

    // MARK: - VPS & Remote Desktop Shield
    private var vpsAndExcludedAppsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(
                icon: "server.rack",
                title: "Lá chắn VPS, Windows App & Terminal",
                color: HudTheme.cyan
            )

            VStack(alignment: .leading, spacing: 8) {
                HudToggleRow(
                    title: "Tự động bỏ qua tiếng Việt trên Windows App / Remote Desktop / VPS",
                    subtitle: "Pass-through 0ms trễ phím cho Windows App, RDC, AnyDesk, RustDesk, TeamViewer, VNC, Termius, Parallels...",
                    isOn: $vm.imeSettings.autoBypassVPSAndRemote,
                    accent: HudTheme.cyan
                )

                HudToggleRow(
                    title: "Tự động dùng Tiếng Anh trong Terminal / iTerm2 / Warp",
                    subtitle: "Tránh gõ nhầm dấu khi gõ lệnh SSH, vim, docker. Vẫn bật lại tiếng Việt thủ công khi cần.",
                    isOn: $vm.imeSettings.autoBypassTerminal,
                    accent: HudTheme.cyan
                )
            }
            .padding(9)
            .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.cyan.opacity(0.18), lineWidth: 0.7))

            let frontBid = vm.frontmostBundleID
            let frontName = vm.frontmostAppName.isEmpty ? frontBid : vm.frontmostAppName
            if !frontBid.isEmpty && frontBid != Bundle.main.bundleIdentifier {
                let isExcluded = vm.imeSettings.excludedBundleIDs.contains(frontBid)
                HStack(spacing: 8) {
                    Image(systemName: isExcluded ? "checkmark.circle.fill" : "app.dashed")
                        .foregroundStyle(isExcluded ? HudTheme.emerald : HudTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("App vừa dùng: \(frontName)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HudTheme.textPrimary)
                        Text(isExcluded ? "Đang loại trừ — luôn gõ Tiếng Anh thuần" : "Thêm vào danh sách loại trừ nếu không muốn gõ tiếng Việt")
                            .font(.system(size: 9.5))
                            .foregroundStyle(HudTheme.textSecondary)
                    }
                    Spacer()
                    HudButton(
                        title: isExcluded ? "Bỏ loại trừ" : "Loại trừ app",
                        color: isExcluded ? HudTheme.emerald : HudTheme.cyan,
                        filled: false,
                        compact: true
                    ) {
                        if isExcluded {
                            vm.removeAppFromExcluded(frontBid)
                        } else {
                            vm.addAppToExcluded(frontBid)
                        }
                    }
                }
                .padding(8)
                .background(isExcluded ? HudTheme.emerald.opacity(0.10) : HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder((isExcluded ? HudTheme.emerald : HudTheme.textMuted).opacity(0.30), lineWidth: 0.7))
            }

            if !vm.imeSettings.excludedBundleIDs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("APP LOẠI TRỪ THỦ CÔNG (\(vm.imeSettings.excludedBundleIDs.count))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(HudTheme.textMuted)

                    ForEach(vm.imeSettings.excludedBundleIDs, id: \.self) { bid in
                        HStack {
                            Text(bid)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(HudTheme.textPrimary)
                            Spacer()
                            Button {
                                vm.removeAppFromExcluded(bid)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(HudTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 1.5)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .hudCard(accent: HudTheme.cyan, chamfer: 9, padding: 11, showBrackets: true)
    }

    // MARK: - Advanced Options
    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(icon: "slider.horizontal.3", title: "Tuỳ chọn bộ gõ chuẩn EVKey", color: HudTheme.cobalt)

            VStack(spacing: 7) {
                HudToggleRow(title: "Tự động khôi phục từ tiếng Anh (reset, test, pause, post, code...)", isOn: $vm.imeSettings.smartEnglishRestore, accent: HudTheme.cobalt)
                HudToggleRow(title: "Kiểm tra chính tả & bảo vệ từ tiếng Anh / URL", isOn: $vm.imeSettings.spellCheckEnabled, accent: HudTheme.cobalt)
                HudToggleRow(title: "Vá thanh địa chỉ & gợi ý Chrome / Safari / Spotlight", isOn: $vm.imeSettings.fixChromiumAutocomplete, accent: HudTheme.cobalt)
                HudToggleRow(title: "Đặt dấu kiểu mới (hoà, thuý, uỷ)", isOn: $vm.imeSettings.modernOrthography, accent: HudTheme.cobalt)
                HudToggleRow(title: "Đặt dấu tự do (toans → toán, vuwaf → vừa)", isOn: $vm.imeSettings.freeMark, accent: HudTheme.cobalt)
                HudToggleRow(title: "Nhớ Việt / Anh theo từng ứng dụng (Smart Switch)", isOn: $vm.imeSettings.smartSwitchPerApp, accent: HudTheme.cobalt)
                HudToggleRow(title: "Phím Esc khôi phục từ gốc chưa dấu", isOn: $vm.imeSettings.restoreOnEscape, accent: HudTheme.cobalt)
                HudToggleRow(title: "Gõ ngoặc [ ] thành ơ, ư (u[ → ươ, gõ đúp ra ngoặc)", isOn: $vm.imeSettings.bracketShortcuts, accent: HudTheme.cobalt)
                HudToggleRow(title: "Gõ W đứng đầu thành Ư (tắt để gõ www thoải mái)", isOn: $vm.imeSettings.standaloneWAsU, accent: HudTheme.cobalt)
                HudToggleRow(title: "Gõ nhanh phụ âm đầu (Quick Telex: cc=ch, kk=kh, nn=ng...)", isOn: $vm.imeSettings.quickTelex, accent: HudTheme.cobalt)
                HudToggleRow(title: "Dùng phím Caps Lock để chuyển Việt / Anh", isOn: $vm.imeSettings.useCapsLockToSwitch, accent: HudTheme.cobalt)
                HudToggleRow(title: "Tự động viết hoa đầu câu", isOn: $vm.imeSettings.autoCapitalize, accent: HudTheme.cobalt)
                HudToggleRow(title: "Âm báo nhẹ khi bấm chuyển Việt / Anh", isOn: $vm.imeSettings.soundOnSwitch, accent: HudTheme.cobalt)
            }

            if vm.imeSettings.smartSwitchPerApp {
                HStack {
                    Text("Đã ghi nhớ trạng thái cho \(vm.perAppCount) ứng dụng")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HudTheme.textSecondary)
                    Spacer()
                    if vm.perAppCount > 0 {
                        HudButton(title: "Xoá nhớ app", color: HudTheme.amber, filled: false, compact: true) {
                            vm.clearPerAppMemory()
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .hudCard(accent: HudTheme.cobalt.opacity(0.55), chamfer: 9, padding: 11)
    }

    // MARK: - Macro Table
    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HudToggleRow(
                title: "Bảng gõ tắt (Macro)",
                subtitle: "Tự mở rộng từ viết tắt khi nhấn Space / Enter",
                isOn: $vm.imeSettings.macroEnabled,
                accent: HudTheme.violet
            )

            if vm.imeSettings.macroEnabled {
                Rectangle().fill(HudTheme.violet.opacity(0.25)).frame(height: 0.7)

                HStack(spacing: 6) {
                    TextField("Từ tắt (vd: vn)", text: $newMacroKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HudTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5.5)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(HudTheme.violet.opacity(0.35), lineWidth: 0.75))
                        .frame(width: 96)

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.violet)

                    TextField("Thay bằng (vd: Việt Nam)", text: $newMacroValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(HudTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5.5)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(HudTheme.violet.opacity(0.35), lineWidth: 0.75))

                    HudButton(
                        title: "Thêm",
                        color: HudTheme.violet,
                        filled: true,
                        compact: true,
                        disabled: newMacroKey.trimmingCharacters(in: .whitespaces).isEmpty || newMacroValue.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        vm.addMacro(key: newMacroKey, value: newMacroValue)
                        newMacroKey = ""
                        newMacroValue = ""
                    }
                }

                let sortedKeys = vm.imeSettings.macroTable.keys.sorted()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 6)], spacing: 6) {
                    ForEach(sortedKeys, id: \.self) { key in
                        if let val = vm.imeSettings.macroTable[key] {
                            HStack(spacing: 4) {
                                Text(key)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(HudTheme.cyan)
                                Text("→ \(val)")
                                    .font(.caption2)
                                    .foregroundStyle(HudTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Button {
                                    vm.removeMacro(key: key)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(HudTheme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(HudTheme.violet.opacity(0.22), lineWidth: 0.6))
                        }
                    }
                }

                HStack {
                    Text("\(vm.imeSettings.macroTable.count) từ gõ tắt")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HudTheme.textMuted)
                    Spacer()
                    HudButton(title: "Đặt lại mặc định", color: HudTheme.textSecondary, filled: false, compact: true) {
                        vm.resetMacrosToDefault()
                    }
                }
            }
        }
        .hudCard(accent: HudTheme.violet.opacity(0.5), chamfer: 9, padding: 11)
    }

    // MARK: - Live Scratchpad
    private var scratchpadCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionEyebrow(
                    icon: "character.cursor.ibeam",
                    title: "Khung gõ thử trực tiếp",
                    color: vm.imeSettings.isEnabled ? HudTheme.cyan : HudTheme.textMuted
                )
                if !vm.imeScratchpad.isEmpty {
                    HudButton(title: "Xoá", color: HudTheme.textSecondary, filled: false, compact: true) {
                        vm.imeScratchpad = ""
                    }
                }
            }
            TextField("Gõ thử: vừa, quá, reset, pause, test, thương, tiếng Việt...", text: $vm.imeScratchpad)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(HudTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7.5)
                .background(HudTheme.insetBg, in: ChamferedRect(cut: 5, cornerRadius: 3))
                .overlay(ChamferedRect(cut: 5, cornerRadius: 3).strokeBorder(HudTheme.cyan.opacity(0.40), lineWidth: 0.85))
        }
        .hudCard(accent: HudTheme.cyan.opacity(0.55), chamfer: 9, padding: 11)
    }
}
