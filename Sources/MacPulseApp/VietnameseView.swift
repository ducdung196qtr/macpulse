import SwiftUI
import MacPulseCore

struct VietnameseView: View {
    @ObservedObject var vm: AppViewModel
    @State private var newMacroKey: String = ""
    @State private var newMacroValue: String = ""
    @State private var showAddMacroSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                accessibilityBanner
                conflictBanner
                systemInputSourceBanner
                modeAndHotkeyCard
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

    @ViewBuilder
    private var accessibilityBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: vm.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(vm.isAccessibilityTrusted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.isAccessibilityTrusted ? "Bộ gõ cấp hệ thống đã sẵn sàng" : "Cần cấp quyền Trợ năng (Accessibility)")
                    .font(.subheadline.weight(.semibold))
                Text(vm.imeStatusSummary)
                    .font(.caption)
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
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 8)
                    .fill((vm.isAccessibilityTrusted ? Color.green : Color.orange).opacity(0.06))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder((vm.isAccessibilityTrusted ? Color.green : Color.orange).opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var conflictBanner: some View {
        if !vm.conflictingApps.isEmpty {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phát hiện bộ gõ khác đang chạy song song")
                        .font(.subheadline.weight(.semibold))
                    Text("\(vm.conflictingApps.map(\.name).joined(separator: ", ")) đang hoạt động. Tắt để tránh gõ đúp dấu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tắt ngay") {
                    vm.terminateConflictingInputApps()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.06))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.red.opacity(0.28), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var systemInputSourceBanner: some View {
        if vm.isSystemVietnameseInputSourceActive {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("Bàn phím macOS hiện đang chọn nguồn \(vm.systemInputSourceID). Hãy chuyển thanh input menu của macOS về ABC / U.S. để MacPulse gõ mượt như EVKey.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.06))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.blue.opacity(0.22), lineWidth: 1)
            )
        }
    }

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
                        Text("Bật gõ Tiếng Việt kiểu EVKey")
                            .font(.subheadline.weight(.semibold))
                        Text("Bắt phím trực tiếp bằng CGEventTap (0 thư viện ngoài)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Divider()

            HStack {
                Text("Kiểu gõ")
                    .font(.subheadline.weight(.medium))
                Spacer()
                HStack(spacing: 4) {
                    ForEach(VietnameseInputMethod.allCases) { method in
                        let selected = vm.imeSettings.inputMethod == method
                        Button {
                            vm.imeSettings.inputMethod = method
                        } label: {
                            Text(method.displayName)
                                .font(.caption.weight(selected ? .semibold : .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selected ? Color.accentColor : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Phím chuyển Việt / Anh")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    ForEach(VietnameseHotkey.allCases) { hk in
                        let selected = vm.imeSettings.hotkey == hk
                        Button {
                            vm.imeSettings.hotkey = hk
                        } label: {
                            HStack(spacing: 4) {
                                Text(hotkeySymbols(hk))
                                    .font(.system(size: 11, weight: .bold))
                                    .opacity(0.85)
                                Text(hk.displayName)
                                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(selected ? Color.accentColor : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func hotkeySymbols(_ hk: VietnameseHotkey) -> String {
        switch hk {
        case .ctrlShift: return "⌃ ⇧"
        case .cmdShift: return "⌘ ⇧"
        case .optionZ: return "⌥ Z"
        case .ctrlSpace: return "⌃ ␣"
        case .capsLock: return "⇪ Caps"
        }
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tuỳ chọn nâng cao kiểu EVKey")
                .font(.headline)

            Toggle("Tự động khôi phục từ tiếng Anh (post, get, user, login, code...)", isOn: $vm.imeSettings.smartEnglishRestore)
                .font(.subheadline)
            Toggle("Gõ nhanh phụ âm đầu (Quick Telex: cc=ch, kk=kh, nn=ng, tt=th...)", isOn: $vm.imeSettings.quickTelex)
                .font(.subheadline)
            Toggle("Dùng phím Caps Lock để chuyển Việt / Anh", isOn: $vm.imeSettings.useCapsLockToSwitch)
                .font(.subheadline)
            Toggle("Tự động viết hoa đầu câu (sau dấu chấm, hỏi, than)", isOn: $vm.imeSettings.autoCapitalize)
                .font(.subheadline)
            Toggle("Đặt dấu kiểu mới (hoà, thuý, uỷ)", isOn: $vm.imeSettings.modernOrthography)
                .font(.subheadline)
            Toggle("Đặt dấu tự do (gõ dấu sau phụ âm cuối: toans -> toán)", isOn: $vm.imeSettings.freeMark)
                .font(.subheadline)
            Toggle("Kiểm tra chính tả & bảo vệ từ tiếng Anh (code, URL)", isOn: $vm.imeSettings.spellCheckEnabled)
                .font(.subheadline)
            Toggle("Gõ ngoặc [ ] thành ơ, ư (u[ thành ươ, gõ đúp ra ngoặc)", isOn: $vm.imeSettings.bracketShortcuts)
                .font(.subheadline)
            Toggle("Phím Esc khôi phục từ gốc chưa dấu", isOn: $vm.imeSettings.restoreOnEscape)
                .font(.subheadline)
            Toggle("Vá thanh địa chỉ Chrome / Safari / Spotlight", isOn: $vm.imeSettings.fixChromiumAutocomplete)
                .font(.subheadline)
            Toggle("Âm báo nhẹ khi bấm chuyển Việt / Anh", isOn: $vm.imeSettings.soundOnSwitch)
                .font(.subheadline)
            Toggle("Nhớ Việt / Anh theo từng ứng dụng (Smart Switch)", isOn: $vm.imeSettings.smartSwitchPerApp)
                .font(.subheadline)
            Toggle("Gõ W đứng đầu thành Ư (tắt để gõ www thoải mái)", isOn: $vm.imeSettings.standaloneWAsU)
                .font(.subheadline)

            if vm.imeSettings.smartSwitchPerApp {
                HStack {
                    Text("App gần nhất: \(vm.frontmostAppName.isEmpty ? "MacPulse" : vm.frontmostAppName) • Đã nhớ \(vm.perAppCount) app")
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
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bảng gõ tắt (Macro)")
                        .font(.headline)
                    Text("Tự mở rộng từ viết tắt khi nhấn Space")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $vm.imeSettings.macroEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if vm.imeSettings.macroEnabled {
                Divider()

                // Macro input form
                HStack(spacing: 6) {
                    TextField("Từ tắt (vd: vn)", text: $newMacroKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
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
                    .disabled(newMacroKey.trimmingCharacters(in: .whitespaces).isEmpty || newMacroValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Macro pills grid
                let sortedKeys = vm.imeSettings.macroTable.keys.sorted()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                    ForEach(sortedKeys, id: \.self) { key in
                        if let val = vm.imeSettings.macroTable[key] {
                            HStack(spacing: 4) {
                                Text(key)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.accentColor)
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
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var scratchpadCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Gõ thử trực tiếp")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !vm.imeScratchpad.isEmpty {
                    Button("Xoá chữ") {
                        vm.imeScratchpad = ""
                    }
                    .controlSize(.mini)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(vm.imeSettings.isEnabled ? Color.blue : Color.gray)
                        .frame(width: 6, height: 6)
                    Text("Đang ở chế độ \(vm.imeSettings.isEnabled ? "Tiếng Việt (\(vm.imeSettings.inputMethod.displayName))" : "English")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(vm.imeSettings.isEnabled ? .blue : .secondary)
                }
            }
            TextField("Gõ thử: thuongw, tieengs Vieetj, m[, thu[cs, vn, ko, dc...", text: $vm.imeScratchpad)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            if !vm.imeScratchpad.isEmpty {
                HStack(spacing: 8) {
                    Text("Đã gõ: \(vm.imeScratchpad.split(separator: " ").count) từ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Khôi phục: bấm Esc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
