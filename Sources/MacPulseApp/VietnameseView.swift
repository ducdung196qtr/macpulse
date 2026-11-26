import SwiftUI
import MacPulseCore

private enum IMESubTab: String, CaseIterable, Identifiable {
    case basic = "Cơ bản"
    case advanced = "Nâng cao & Gõ tắt"
    var id: String { rawValue }
}

struct VietnameseView: View {
    @ObservedObject var vm: AppViewModel
    @State private var selectedSubTab: IMESubTab = .basic
    @State private var newMacroKey: String = ""
    @State private var newMacroValue: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HudSegmentedBar(
                items: [
                    HudSegmentItem(id: .basic, title: "Cơ bản", icon: "keyboard", dotColor: (!vm.isAccessibilityTrusted || !vm.conflictingApps.isEmpty) ? HudTheme.amber : nil),
                    HudSegmentItem(id: .advanced, title: "Nâng cao & Gõ tắt", icon: "slider.horizontal.3", badge: "\(vm.imeSettings.macroTable.count)")
                ],
                selection: $selectedSubTab,
                accent: HudTheme.cyan
            )
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch selectedSubTab {
                    case .basic:
                        basicWorkspace
                    case .advanced:
                        advancedWorkspace
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            vm.refreshIMEEnvironment()
        }
    }

    // =========================================================================
    // MARK: - SUB-TAB 1: CƠ BẢN (Trạng thái, Kiểu gõ, Phím tắt, VPS, Gõ thử)
    // =========================================================================
    private var basicWorkspace: some View {
        VStack(alignment: .leading, spacing: 10) {
            engineControlCockpit
            secureInputBanner
            conflictBanner
            systemInputSourceBanner
            modeAndHotkeyCard
            vpsAndExcludedAppsCard
            scratchpadCard
        }
    }

    // Unified Engine Status + Master Switch Cockpit
    private var engineControlCockpit: some View {
        let ready = vm.isAccessibilityTrusted && vm.tapRuntimeState == .running
        let accent: Color = ready ? (vm.imeSettings.isEnabled ? HudTheme.emerald : HudTheme.textMuted) : HudTheme.amber

        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: ready ? "keyboard.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("BỘ GÕ TIẾNG VIỆT EVKEY")
                        .font(.system(size: 11.5, weight: .black, design: .monospaced))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text(ready ? (vm.imeSettings.isEnabled ? "ĐANG BẬT" : "ĐANG TẮT") : "CHỜ QUYỀN")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(accent.opacity(0.20), in: Capsule())
                        .foregroundStyle(accent)
                }
                Text(vm.imeStatusSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(HudTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if !vm.isAccessibilityTrusted {
                HudButton(title: "Cấp quyền", icon: "lock.open.fill", color: HudTheme.amber, filled: true, compact: true) {
                    vm.requestAccessibilityPermission()
                    vm.openAccessibilitySettings()
                }
            } else {
                Button {
                    vm.toggleVietnameseEnabled()
                } label: {
                    let isOn = vm.imeSettings.isEnabled
                    ZStack(alignment: isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(isOn ? HudTheme.emerald.opacity(0.28) : HudTheme.insetBg)
                            .overlay(Capsule().strokeBorder(isOn ? HudTheme.emerald.opacity(0.85) : HudTheme.textMuted.opacity(0.45), lineWidth: 1))
                            .frame(width: 38, height: 20)
                        Circle()
                            .fill(isOn ? HudTheme.emerald : HudTheme.textMuted)
                            .frame(width: 14, height: 14)
                            .padding(.horizontal, 3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .hudCard(accent: accent, chamfer: 9, padding: 11, showBrackets: true)
    }

    @ViewBuilder
    private var secureInputBanner: some View {
        if vm.isSecureInputBlocked {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(HudTheme.amber)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("macOS Secure Input đang khóa bộ gõ")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text(vm.secureInputHolderName.map { "\($0) đang giữ Secure Input. Rời ô mật khẩu hoặc thoát app đó, bộ gõ sẽ tự chạy lại." }
                         ?? "Đang ở ô mật khẩu hoặc app bảo mật. Rời ô mật khẩu để tiếp tục gõ tiếng Việt.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                }
                Spacer()
            }
            .cleanCard(accent: HudTheme.amber, cornerRadius: 8, padding: 9)
        }
    }

    @ViewBuilder
    private var conflictBanner: some View {
        if !vm.conflictingApps.isEmpty {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(HudTheme.crimson)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("Bộ gõ khác đang chạy song song")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text("\(vm.conflictingApps.map(\.name).joined(separator: ", ")) — tắt để tránh đúp dấu.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                }
                Spacer()
                HudButton(title: "Tắt ngay", color: HudTheme.crimson, filled: true, compact: true) {
                    vm.terminateConflictingInputApps()
                }
            }
            .cleanCard(accent: HudTheme.crimson, cornerRadius: 8, padding: 9)
        }
    }

    @ViewBuilder
    private var systemInputSourceBanner: some View {
        if vm.isSystemVietnameseInputSourceActive {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "keyboard.badge.exclamationmark")
                    .foregroundStyle(HudTheme.cyan)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("macOS đang bật nguồn Tiếng Việt")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HudTheme.textPrimary)
                    Text("Chuyển về ABC / U.S. để MacPulse bắt phím chuẩn 100%.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                }
                Spacer()
                HudButton(title: "Chuyển ABC", color: HudTheme.cyan, filled: true, compact: true) {
                    vm.switchSystemInputSourceToABC()
                }
            }
            .cleanCard(accent: HudTheme.cyan, cornerRadius: 8, padding: 9)
        }
    }

    private var modeAndHotkeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                                .background(selected ? HudTheme.cobalt.opacity(0.28) : HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? HudTheme.cyan.opacity(0.8) : HudTheme.borderSubtle.opacity(0.35), lineWidth: 0.75))
                                .foregroundStyle(selected ? HudTheme.textPrimary : HudTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Rectangle().fill(HudTheme.borderSubtle.opacity(0.3)).frame(height: 0.7)

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
                            .background(selected ? HudTheme.cyan.opacity(0.18) : HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? HudTheme.cyan.opacity(0.75) : HudTheme.borderSubtle.opacity(0.32), lineWidth: 0.75))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cleanCard(padding: 11)
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

    private var vpsAndExcludedAppsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LÁ CHẮN VPS, REMOTE & TERMINAL")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
                Spacer()
                if vm.isFrontmostAppBypassed && !vm.frontmostAppName.isEmpty {
                    Text("BYPASS: \(vm.frontmostAppName.uppercased())")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(HudTheme.cyan.opacity(0.16), in: Capsule())
                        .foregroundStyle(HudTheme.cyan)
                }
            }

            HudToggleRow(
                title: "Tự bỏ qua tiếng Việt trên Windows App / Remote / VPS",
                subtitle: "Pass-through 0ms trễ phím cho RDC, AnyDesk, RustDesk, VNC, Parallels...",
                isOn: $vm.imeSettings.autoBypassVPSAndRemote,
                accent: HudTheme.cyan
            )

            HudToggleRow(
                title: "Tự chuyển Tiếng Anh trong Terminal / iTerm2 / Warp",
                subtitle: "Tránh gõ nhầm dấu khi gõ lệnh CLI; vẫn bật lại thủ công khi cần.",
                isOn: $vm.imeSettings.autoBypassTerminal,
                accent: HudTheme.cyan
            )

            let frontBid = vm.frontmostBundleID
            let frontName = vm.frontmostAppName.isEmpty ? frontBid : vm.frontmostAppName
            if !frontBid.isEmpty && frontBid != Bundle.main.bundleIdentifier {
                let isExcluded = vm.imeSettings.excludedBundleIDs.contains(frontBid)
                HStack(spacing: 8) {
                    Image(systemName: isExcluded ? "checkmark.circle.fill" : "app.dashed")
                        .foregroundStyle(isExcluded ? HudTheme.emerald : HudTheme.textMuted)
                    Text("App vừa dùng: \(frontName)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(HudTheme.textPrimary)
                        .lineLimit(1)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
            }

            if !vm.imeSettings.excludedBundleIDs.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("APP LOẠI TRỪ (\(vm.imeSettings.excludedBundleIDs.count))")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HudTheme.textMuted)
                    ForEach(vm.imeSettings.excludedBundleIDs, id: \.self) { bid in
                        HStack {
                            Text(bid)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(HudTheme.textSecondary)
                            Spacer()
                            Button {
                                vm.removeAppFromExcluded(bid)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(HudTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .cleanCard(padding: 11)
    }

    private var scratchpadCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GÕ THỬ TRỰC TIẾP")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
                Spacer()
                if !vm.imeScratchpad.isEmpty {
                    HudButton(title: "Xoá", color: HudTheme.textSecondary, filled: false, compact: true) {
                        vm.imeScratchpad = ""
                    }
                }
            }
            TextField("Gõ thử: tiếng Việt, vừa, quá, reset, test, thương...", text: $vm.imeScratchpad)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(HudTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7.5)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.cyan.opacity(0.38), lineWidth: 0.8))
        }
        .cleanCard(padding: 11)
    }

    // =========================================================================
    // MARK: - SUB-TAB 2: NÂNG CAO & GÕ TẮT
    // =========================================================================
    private var advancedWorkspace: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Group 1: Smart English & Browser Fixes
            VStack(alignment: .leading, spacing: 8) {
                Text("THÔNG MINH ANH – VIỆT & TRÌNH DUYỆT")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
                HudToggleRow(title: "Tự khôi phục từ tiếng Anh (reset, test, pause, code...)", isOn: $vm.imeSettings.smartEnglishRestore, accent: HudTheme.cyan)
                HudToggleRow(title: "Kiểm tra chính tả & bảo vệ từ tiếng Anh / URL", isOn: $vm.imeSettings.spellCheckEnabled, accent: HudTheme.cyan)
                HudToggleRow(title: "Vá thanh địa chỉ Chrome / Safari / Spotlight", isOn: $vm.imeSettings.fixChromiumAutocomplete, accent: HudTheme.cyan)
                HudToggleRow(title: "Nhớ trạng thái Việt / Anh theo từng ứng dụng", isOn: $vm.imeSettings.smartSwitchPerApp, accent: HudTheme.cyan)

                Rectangle().fill(HudTheme.borderSubtle.opacity(0.3)).frame(height: 0.7)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("NHỊP BƠM PHÍM CHỐNG RƠI CHỮ")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(HudTheme.textSecondary)
                        Spacer()
                        Text(vm.activeTapLevelLabel)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(HudTheme.emerald.opacity(0.16), in: Capsule())
                            .foregroundStyle(HudTheme.emerald)
                    }
                    HStack(spacing: 5) {
                        ForEach(IMEInjectionSpeedMode.allCases) { mode in
                            let selected = vm.imeSettings.injectionSpeedMode == mode
                            Button {
                                vm.imeSettings.injectionSpeedMode = mode
                            } label: {
                                Text(mode.displayName)
                                    .font(.system(size: 10.5, weight: selected ? .bold : .medium, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(selected ? HudTheme.cyan.opacity(0.20) : HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? HudTheme.cyan.opacity(0.8) : HudTheme.borderSubtle.opacity(0.32), lineWidth: 0.75))
                                    .foregroundStyle(selected ? HudTheme.textPrimary : HudTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(vm.imeSettings.injectionSpeedMode.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(HudTheme.textMuted)
                }

                if vm.imeSettings.smartSwitchPerApp && vm.perAppCount > 0 {
                    HStack {
                        Text("Đang nhớ \(vm.perAppCount) ứng dụng")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(HudTheme.textMuted)
                        Spacer()
                        HudButton(title: "Xoá bộ nhớ app", color: HudTheme.amber, filled: false, compact: true) {
                            vm.clearPerAppMemory()
                        }
                    }
                }
            }
            .cleanCard(padding: 11)

            // Group 2: Orthography & Shortcuts
            VStack(alignment: .leading, spacing: 8) {
                Text("KIỂU BỎ DẤU & PHÍM TẮT")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(HudTheme.textSecondary)
                HudToggleRow(title: "Đặt dấu kiểu mới (hoà, thuý, uỷ)", isOn: $vm.imeSettings.modernOrthography, accent: HudTheme.cobalt)
                HudToggleRow(title: "Đặt dấu tự do (toans → toán, vuwaf → vừa)", isOn: $vm.imeSettings.freeMark, accent: HudTheme.cobalt)
                HudToggleRow(title: "Phím Esc khôi phục từ gốc chưa dấu", isOn: $vm.imeSettings.restoreOnEscape, accent: HudTheme.cobalt)
                HudToggleRow(title: "Gõ ngoặc [ ] thành ơ, ư (u[ → ươ)", isOn: $vm.imeSettings.bracketShortcuts, accent: HudTheme.cobalt)
                HudToggleRow(title: "Gõ W đứng đầu thành Ư", isOn: $vm.imeSettings.standaloneWAsU, accent: HudTheme.cobalt)
                HudToggleRow(title: "Quick Telex (cc=ch, kk=kh, nn=ng...)", isOn: $vm.imeSettings.quickTelex, accent: HudTheme.cobalt)
                HudToggleRow(title: "Dùng Caps Lock chuyển Việt / Anh", isOn: $vm.imeSettings.useCapsLockToSwitch, accent: HudTheme.cobalt)
                HudToggleRow(title: "Tự viết hoa đầu câu", isOn: $vm.imeSettings.autoCapitalize, accent: HudTheme.cobalt)
                HudToggleRow(title: "Âm báo nhẹ khi chuyển Việt / Anh", isOn: $vm.imeSettings.soundOnSwitch, accent: HudTheme.cobalt)
            }
            .cleanCard(padding: 11)

            // Group 3: Macro Table
            macroCard
        }
    }

    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HudToggleRow(
                title: "Bảng gõ tắt (Macro)",
                subtitle: "Tự mở rộng từ viết tắt khi nhấn Space / Enter",
                isOn: $vm.imeSettings.macroEnabled,
                accent: HudTheme.violet
            )

            if vm.imeSettings.macroEnabled {
                Rectangle().fill(HudTheme.borderSubtle.opacity(0.35)).frame(height: 0.7)

                HStack(spacing: 6) {
                    TextField("Từ tắt (vn)", text: $newMacroKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HudTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5.5)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))
                        .frame(width: 90)

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.violet)

                    TextField("Thay bằng (Việt Nam)", text: $newMacroValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(HudTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5.5)
                        .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 5))

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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], spacing: 6) {
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
                        }
                    }
                }

                HStack {
                    Text("\(vm.imeSettings.macroTable.count) từ gõ tắt")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(HudTheme.textMuted)
                    Spacer()
                    HudButton(title: "Khôi phục mặc định", color: HudTheme.textSecondary, filled: false, compact: true) {
                        vm.resetMacrosToDefault()
                    }
                }
            }
        }
        .cleanCard(padding: 11)
    }
}
