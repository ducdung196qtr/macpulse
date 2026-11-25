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
        let accent: Color = ready ? PulseTheme.emerald : PulseTheme.amber

        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: ready ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ready ? "Bộ gõ Tiếng Việt EVKey Engine" : "Cần cấp quyền Trợ năng (Accessibility)")
                        .font(.system(size: 13, weight: .bold))
                    Text(ready ? "ACTIVE" : "WAITING")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(accent)
                }
                Text(vm.imeStatusSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !vm.isAccessibilityTrusted {
                Button("Cấp quyền") {
                    vm.requestAccessibilityPermission()
                    vm.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.amber)
                .controlSize(.small)
            } else if vm.isFrontmostAppBypassed && !vm.frontmostAppName.isEmpty {
                Text("Bypass: \(vm.frontmostAppName)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(PulseTheme.cyan.opacity(0.14), in: Capsule())
                    .foregroundStyle(PulseTheme.cyan)
            }
        }
        .telemetryCard(accent: accent, cornerRadius: 11, padding: 11)
    }

    @ViewBuilder
    private var conflictBanner: some View {
        if !vm.conflictingApps.isEmpty {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(PulseTheme.crimson)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phát hiện bộ gõ khác đang chạy song song")
                        .font(.caption.weight(.bold))
                    Text("\(vm.conflictingApps.map(\.name).joined(separator: ", ")) đang hoạt động. Tắt để tránh gõ đúp dấu.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tắt ngay") {
                    vm.terminateConflictingInputApps()
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.crimson)
                .controlSize(.small)
            }
            .telemetryCard(accent: PulseTheme.crimson, cornerRadius: 10, padding: 10)
        }
    }

    @ViewBuilder
    private var systemInputSourceBanner: some View {
        if vm.isSystemVietnameseInputSourceActive {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "keyboard.badge.exclamationmark")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseTheme.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text("macOS đang bật nguồn gõ Tiếng Việt (\(vm.systemInputSourceID))")
                        .font(.caption.weight(.semibold))
                    Text("Chuyển macOS về ABC / U.S. để MacPulse bắt phím chính xác 100%.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Chuyển về ABC") {
                    vm.switchSystemInputSourceToABC()
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.cyan)
                .controlSize(.small)
            }
            .telemetryCard(accent: PulseTheme.cyan, cornerRadius: 10, padding: 10)
        }
    }

    // MARK: - Mode & Hotkey Grid (2 Balanced Rows)
    private var modeAndHotkeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: Binding(
                    get: { vm.imeSettings.isEnabled },
                    set: { val in
                        if val != vm.imeSettings.isEnabled { vm.toggleVietnameseEnabled() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bật gõ Tiếng Việt cấp hệ thống")
                            .font(.system(size: 12.5, weight: .bold))
                        Text("CGEventTap thuần Swift • Pacing chống lỗi Chrome/Electron • 0 thư viện ngoài")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Divider().opacity(0.45)

            HStack {
                Text("Kiểu gõ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(VietnameseInputMethod.allCases) { method in
                        let selected = vm.imeSettings.inputMethod == method
                        Button {
                            vm.imeSettings.inputMethod = method
                        } label: {
                            Text(method.displayName)
                                .font(.system(size: 11, weight: selected ? .bold : .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selected ? PulseTheme.cobalt : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6.5))
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Phím tắt chuyển Việt / Anh")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(VietnameseHotkey.allCases) { hk in
                        let selected = vm.imeSettings.hotkey == hk
                        Button {
                            vm.imeSettings.hotkey = hk
                        } label: {
                            HStack(spacing: 5) {
                                Text(hotkeySymbols(hk))
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .opacity(0.9)
                                Text(hk.displayName)
                                    .font(.system(size: 11, weight: selected ? .bold : .medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                            .background(selected ? PulseTheme.cyan.opacity(0.22) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(selected ? PulseTheme.cyan.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 0.9)
                            )
                            .foregroundStyle(selected ? PulseTheme.cyan : Color.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .telemetryCard(cornerRadius: 11, padding: 11)
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
                title: "Bảo vệ gõ trên VPS, Windows App & Terminal",
                color: PulseTheme.cyan
            )

            VStack(alignment: .leading, spacing: 7) {
                Toggle(isOn: $vm.imeSettings.autoBypassVPSAndRemote) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tự động bỏ qua tiếng Việt trên Windows App / Remote Desktop / VPS")
                            .font(.caption.weight(.semibold))
                        Text("Pass-through 0ms trễ phím cho Windows App, RDC, AnyDesk, RustDesk, TeamViewer, VNC, Termius, Parallels...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $vm.imeSettings.autoBypassTerminal) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tự động dùng Tiếng Anh trong Terminal / iTerm2 / Warp")
                            .font(.caption.weight(.semibold))
                        Text("Tránh gõ nhầm dấu khi gõ lệnh SSH, vim, docker. Vẫn bật lại tiếng Việt thủ công khi cần.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))

            let frontBid = vm.frontmostBundleID
            let frontName = vm.frontmostAppName.isEmpty ? frontBid : vm.frontmostAppName
            if !frontBid.isEmpty && frontBid != Bundle.main.bundleIdentifier {
                let isExcluded = vm.imeSettings.excludedBundleIDs.contains(frontBid)
                HStack(spacing: 8) {
                    Image(systemName: isExcluded ? "checkmark.circle.fill" : "app.dashed")
                        .foregroundStyle(isExcluded ? PulseTheme.emerald : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("App vừa dùng: \(frontName)")
                            .font(.caption.weight(.semibold))
                        Text(isExcluded ? "Đang loại trừ — luôn gõ Tiếng Anh thuần" : "Thêm vào danh sách loại trừ nếu không muốn gõ tiếng Việt trên app này")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isExcluded ? "Bỏ loại trừ" : "Loại trừ app này") {
                        if isExcluded {
                            vm.removeAppFromExcluded(frontBid)
                        } else {
                            vm.addAppToExcluded(frontBid)
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background((isExcluded ? PulseTheme.emerald.opacity(0.09) : Color.primary.opacity(0.03)), in: RoundedRectangle(cornerRadius: 7))
            }

            if !vm.imeSettings.excludedBundleIDs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App đã loại trừ thủ công (\(vm.imeSettings.excludedBundleIDs.count)):")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(vm.imeSettings.excludedBundleIDs, id: \.self) { bid in
                        HStack {
                            Text(bid)
                                .font(.system(size: 10.5, design: .monospaced))
                            Spacer()
                            Button {
                                vm.removeAppFromExcluded(bid)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 1.5)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .telemetryCard(accent: PulseTheme.cyan, cornerRadius: 11, padding: 11)
    }

    // MARK: - Advanced Options
    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionEyebrow(icon: "slider.horizontal.3", title: "Tuỳ chọn bộ gõ chuẩn EVKey", color: PulseTheme.cobalt)

            Group {
                Toggle("Tự động khôi phục từ tiếng Anh (reset, test, pause, post, code...)", isOn: $vm.imeSettings.smartEnglishRestore)
                Toggle("Kiểm tra chính tả & bảo vệ từ tiếng Anh / URL", isOn: $vm.imeSettings.spellCheckEnabled)
                Toggle("Vá thanh địa chỉ & gợi ý Chrome / Safari / Spotlight", isOn: $vm.imeSettings.fixChromiumAutocomplete)
                Toggle("Đặt dấu kiểu mới (hoà, thuý, uỷ)", isOn: $vm.imeSettings.modernOrthography)
                Toggle("Đặt dấu tự do (toans → toán, vuwaf → vừa)", isOn: $vm.imeSettings.freeMark)
                Toggle("Nhớ Việt / Anh theo từng ứng dụng (Smart Switch)", isOn: $vm.imeSettings.smartSwitchPerApp)
                Toggle("Phím Esc khôi phục từ gốc chưa dấu", isOn: $vm.imeSettings.restoreOnEscape)
                Toggle("Gõ ngoặc [ ] thành ơ, ư (u[ → ươ, gõ đúp ra ngoặc)", isOn: $vm.imeSettings.bracketShortcuts)
                Toggle("Gõ W đứng đầu thành Ư (tắt để gõ www thoải mái)", isOn: $vm.imeSettings.standaloneWAsU)
                Toggle("Gõ nhanh phụ âm đầu (Quick Telex: cc=ch, kk=kh, nn=ng...)", isOn: $vm.imeSettings.quickTelex)
                Toggle("Dùng phím Caps Lock để chuyển Việt / Anh", isOn: $vm.imeSettings.useCapsLockToSwitch)
                Toggle("Tự động viết hoa đầu câu", isOn: $vm.imeSettings.autoCapitalize)
                Toggle("Âm báo nhẹ khi bấm chuyển Việt / Anh", isOn: $vm.imeSettings.soundOnSwitch)
            }
            .font(.system(size: 11.5))

            if vm.imeSettings.smartSwitchPerApp {
                HStack {
                    Text("Đã ghi nhớ trạng thái cho \(vm.perAppCount) ứng dụng")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if vm.perAppCount > 0 {
                        Button("Xoá nhớ app") {
                            vm.clearPerAppMemory()
                        }
                        .controlSize(.mini)
                    }
                }
                .padding(.top, 2)
            }
        }
        .telemetryCard(cornerRadius: 11, padding: 11)
    }

    // MARK: - Macro Table
    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bảng gõ tắt (Macro)")
                        .font(.system(size: 12.5, weight: .bold))
                    Text("Tự mở rộng từ viết tắt khi nhấn Space / Enter")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $vm.imeSettings.macroEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if vm.imeSettings.macroEnabled {
                Divider().opacity(0.45)

                HStack(spacing: 6) {
                    TextField("Từ tắt (vd: vn)", text: $newMacroKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Thay bằng (vd: Việt Nam)", text: $newMacroValue)
                        .textFieldStyle(.roundedBorder)
                    Button("Thêm") {
                        vm.addMacro(key: newMacroKey, value: newMacroValue)
                        newMacroKey = ""
                        newMacroValue = ""
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.cobalt)
                    .disabled(newMacroKey.trimmingCharacters(in: .whitespaces).isEmpty || newMacroValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                let sortedKeys = vm.imeSettings.macroTable.keys.sorted()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 6)], spacing: 6) {
                    ForEach(sortedKeys, id: \.self) { key in
                        if let val = vm.imeSettings.macroTable[key] {
                            HStack(spacing: 4) {
                                Text(key)
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(PulseTheme.cyan)
                                Text("→ \(val)")
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Button {
                                    vm.removeMacro(key: key)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                HStack {
                    Text("\(vm.imeSettings.macroTable.count) từ gõ tắt")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Đặt lại mặc định") {
                        vm.resetMacrosToDefault()
                    }
                    .controlSize(.mini)
                }
            }
        }
        .telemetryCard(cornerRadius: 11, padding: 11)
    }

    // MARK: - Live Scratchpad
    private var scratchpadCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionEyebrow(
                    icon: "character.cursor.ibeam",
                    title: "Khung gõ thử trực tiếp",
                    color: vm.imeSettings.isEnabled ? PulseTheme.cyan : .secondary
                )
                if !vm.imeScratchpad.isEmpty {
                    Button("Xoá") { vm.imeScratchpad = "" }
                        .controlSize(.mini)
                }
            }
            TextField("Gõ thử: vừa, quá, reset, pause, test, thương, tiếng Việt...", text: $vm.imeScratchpad)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
        }
        .telemetryCard(cornerRadius: 11, padding: 11)
    }
}
