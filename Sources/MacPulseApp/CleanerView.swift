import SwiftUI
import MacPulseCore

struct CleanerView: View {
    @ObservedObject var vm: AppViewModel

    private var visibleFilter: CleanerFocusSection {
        vm.cleanerFocus
    }

    var body: some View {
        VStack(spacing: 0) {
            cleanerFilterHeader
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let pending = vm.pendingTerminationGroup {
                        InlineConfirmTerminationCard(group: pending, vm: vm)
                    }

                    if vm.showTabInspector {
                        BrowserTabsInspectorCard(vm: vm)
                    }

                    if let msg = vm.cleanupOutcomeMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(msg)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    heroSummaryCard

                    chromeRescueCard

                    if visibleFilter == .all || visibleFilter == .ai {
                        aiSection
                    }

                    if visibleFilter == .all || visibleFilter == .browser {
                        browserSection
                    }

                    if visibleFilter == .all || visibleFilter == .developer {
                        developerSection
                    }

                    if visibleFilter == .all || visibleFilter == .logs {
                        logsSection
                    }

                    if visibleFilter == .all || visibleFilter == .storage {
                        storageHeavySection
                    }

                    if visibleFilter == .all || visibleFilter == .ram {
                        ramSection
                    }
                }
                .padding(14)
            }

            Divider()
            cleanerFooterBar
        }
    }

    private var cleanerFilterHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                filterButton("Tất cả", section: .all, countText: Formatters.bytes(vm.totalSafeCacheBytes))
                filterButton("Rác AI", section: .ai, countText: Formatters.bytes(vm.totalAIGarbageBytes))
                filterButton("Trình duyệt", section: .browser, countText: Formatters.bytes(vm.totalBrowserCacheBytes))
                filterButton("Lập trình", section: .developer, countText: Formatters.bytes(vm.totalDeveloperBuildBytes))
                filterButton("Log & Rác", section: .logs, countText: Formatters.bytes(vm.totalLogsAndTrashBytes))
                filterButton("Bộ nhớ lớn", section: .storage, countText: Formatters.bytes(vm.totalHeavyStorageBytes))
                filterButton("RAM", section: .ram, countText: Formatters.bytes(vm.estimatedReclaimableRAMBytes))
            }
            .padding(3)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 14)
    }

    private func filterButton(_ label: String, section: CleanerFocusSection, countText: String) -> some View {
        let active = vm.cleanerFocus == section
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                vm.cleanerFocus = section
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: section.icon)
                    .font(.caption2)
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                if countText != "0 B" && countText != "0.0 B" {
                    Text(countText)
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background((active ? Color.white.opacity(0.25) : Color.primary.opacity(0.08)), in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(active ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var heroSummaryCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        Text("Rác AI & Cache SSD")
                            .font(.caption.weight(.bold))
                    }
                    Text("Tìm thấy \(Formatters.bytes(vm.totalSafeCacheBytes)) rác an toàn")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                    Text("Tự tạo lại khi cần, 0% mất tài khoản/code")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Color.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "memorychip")
                            .foregroundStyle(.blue)
                        Text("RAM khả dụng")
                            .font(.caption.weight(.bold))
                    }
                    if let mem = vm.snapshot?.memory {
                        Text(String(format: "Trống %.1f GB (Nén %.1fG)", mem.availableGB, mem.compressedGB))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                    }
                    Text("Thu hồi ~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes)) từ app thừa")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                HStack(spacing: 8) {
                    Button("Chọn tất cả an toàn") {
                        vm.selectAllSafe()
                    }
                    .controlSize(.mini)

                    Button("Bỏ chọn hết") {
                        vm.deselectAll()
                    }
                    .controlSize(.mini)
                }

                Spacer()

                if vm.totalSelectedCleanupBytes > 0 {
                    Button(vm.isCleaning ? "Đang dọn..." : "Dọn ngay (\(Formatters.bytes(vm.totalSelectedCleanupBytes)))") {
                        vm.runSelectedCleanup()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .disabled(vm.isCleaning)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Rác do AI tạo ra (Cursor, Codex, Claude, Gemini)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(Formatters.bytes(vm.totalAIGarbageBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.purple)
            }

            Text("Tệp đệm phiên, logs, runtime tạm và cache phản hồi của các trợ lý AI. Xoá hoàn toàn an toàn, không ảnh hưởng API key, prompt hay cấu hình.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if vm.aiCandidates.isEmpty {
                Text("Không phát hiện tệp rác AI nào đáng kể.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ForEach(vm.aiCandidates) { item in
                    CleanupRowView(item: item, vm: vm)
                }
            }
        }
    }

    private var browserSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.blue)
                Text("Cache Trình duyệt Web (Chrome, Safari, Edge, Arc)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(Formatters.bytes(vm.totalBrowserCacheBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.blue)
            }

            Text("Tệp hình ảnh, stylesheet đệm tạm và GPU/Shader. Giữ nguyên 100% mật khẩu, tài khoản đăng nhập, bookmark và tab đang duyệt.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if vm.browserCandidates.isEmpty {
                Text("Không có cache trình duyệt lớn cần dọn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ForEach(vm.browserCandidates) { item in
                    CleanupRowView(item: item, vm: vm)
                }
            }
        }
    }

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.orange)
                Text("Cache Lập trình & Build (Xcode, npm, Homebrew, pip)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(Formatters.bytes(vm.totalDeveloperBuildBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Text("Gói tải về và tệp trung gian build. Xcode / npm / brew sẽ tự động tải lại khi bạn build hoặc install.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if vm.developerCandidates.isEmpty {
                Text("Không có cache lập trình nào cần dọn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ForEach(vm.developerCandidates) { item in
                    CleanupRowView(item: item, vm: vm)
                }
            }
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.yellow)
                Text("File Log phình to & Rác hệ thống")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(Formatters.bytes(vm.totalLogsAndTrashBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.yellow)
            }

            Text("Tệp log web/server phình to (cắt rỗng an toàn), thumbnail QuickLook và Thùng rác.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(vm.logAndTrashCandidates) { item in
                CleanupRowView(item: item, vm: vm)
            }
        }
    }

    private var storageHeavySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(.purple)
                Text("Dữ liệu lớn trên ổ cứng (Chỉ xem Finder)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(Formatters.bytes(vm.totalHeavyStorageBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.purple)
            }

            Text("Dữ liệu runtime, database cục bộ hoặc build Xcode dung lượng lớn. MacPulse chỉ mở Finder để bạn tự kiểm tra, KHÔNG tự ý xoá.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(vm.storageHeavyCandidates) { item in
                CleanupRowView(item: item, vm: vm)
            }
        }
    }

    private var ramSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "memorychip.fill")
                    .foregroundStyle(.blue)
                Text("Giải phóng RAM (Bộ nhớ đang chạy)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("Thu hồi tối đa ~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.blue)
            }

            Text("macOS giải phóng RAM thật bằng cách đóng app đang rảnh hoặc tab thừa (không dùng lệnh ảo gây giật). Rê chuột vào ⓘ trước khi bấm Đóng.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Soi & đóng từng tab trình duyệt") {
                    vm.scanBrowserTabs()
                }
                .controlSize(.small)

                if let orphan = vm.processGroups.first(where: { $0.isOrphanAutomation }) {
                    Button("Dọn Chrome ngầm (\(Formatters.bytes(orphan.totalRSSBytes)))") {
                        vm.requestCloseProcess(orphan)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
            }

            VStack(spacing: 6) {
                ForEach(vm.ramReclaimableGroups) { group in
                    ProcessRowView(group: group, vm: vm, highlightRAM: true)
                }
            }
        }
    }

    private var chromeRescueCard: some View {
        let chromeCacheSize = vm.browserCandidates.first(where: { $0.id == "cache-chrome" })?.sizeBytes ?? 0
        let hasOrphan = vm.processGroups.contains(where: { $0.isOrphanAutomation })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.blue)
                Text("Sửa lỗi & Dọn sạch Chrome (1-Click)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if chromeCacheSize > 0 {
                    Text(Formatters.bytes(chromeCacheSize))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }

            Text(hasOrphan
                 ? "Phát hiện Chrome headless/automation đang chạy ngầm (có thể chặn mở Chrome). Bấm nút dưới để dọn sạch toàn bộ tiến trình kẹt, gỡ SingletonLock & xoá sạch Cache."
                 : "Khi Chrome bị lag, ăn CPU cao hoặc bấm không mở được: đóng sạch Chrome & tiến trình ngầm kẹt, gỡ lock, xoá GPU/Shader & Service Worker Cache (giữ nguyên tài khoản, mật khẩu, bookmark) và mở lại Chrome.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(vm.isRescuingChrome ? "Đang sửa Chrome..." : "Sửa lỗi & Mở lại Chrome") {
                    vm.rescueAndCleanChrome(relaunch: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .disabled(vm.isRescuingChrome || vm.isCleaning)

                Button("Chỉ dọn sạch") {
                    vm.rescueAndCleanChrome(relaunch: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.isRescuingChrome || vm.isCleaning)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
        )
    }

    private var cleanerFooterBar: some View {
        HStack {
            Button("Quét lại SSD") {
                vm.scanCleanup()
            }
            .controlSize(.small)

            Spacer()

            Text("Đã chọn: \(Formatters.bytes(vm.totalSelectedCleanupBytes))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(vm.isCleaning ? "Đang dọn..." : "Dọn rác đã chọn") {
                vm.runSelectedCleanup()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(vm.isCleaning || vm.totalSelectedCleanupBytes == 0)
        }
        .padding(12)
    }
}

private struct CleanupRowView: View {
    let item: CleanupCandidate
    @ObservedObject var vm: AppViewModel

    private var itemIcon: (name: String, color: Color) {
        let id = item.id.lowercased()
        if id.contains("ai") || id.contains("cursor") || id.contains("codex") || id.contains("claude") || id.contains("gemini") {
            return ("sparkles", .purple)
        }
        if id.contains("chrome") { return ("globe", .blue) }
        if id.contains("safari") { return ("safari", .blue) }
        if id.contains("edge") { return ("globe.americas.fill", .cyan) }
        if id.contains("arc") { return ("globe.europe.africa.fill", .indigo) }
        if id.contains("vscode") { return ("chevron.left.forwardslash.chevron.right", .blue) }
        if id.contains("brew") || id.contains("homebrew") { return ("cup.and.saucer.fill", .orange) }
        if id.contains("npm") || id.contains("yarn") || id.contains("pnpm") { return ("shippingbox.fill", .red) }
        if id.contains("swiftpm") || id.contains("xcode") { return ("hammer.fill", .orange) }
        if id.contains("pip") || id.contains("uv") || id.contains("python") { return ("terminal.fill", .indigo) }
        if id.contains("trash") { return ("trash.fill", .red) }
        if id.contains("log") { return ("doc.text.fill", .yellow) }
        if id.contains("db") { return ("cylinder.split.1x2.fill", .purple) }
        if id.contains("quicklook") { return ("eye.fill", .teal) }
        return ("tray.full.fill", .green)
    }

    private var safetyBadge: (label: String, color: Color) {
        if item.tier == .inspectOnly {
            return ("Chỉ kiểm tra", .purple)
        }
        if item.defaultSelected {
            return ("An toàn 100%", .green)
        }
        return ("Tự chọn", .orange)
    }

    var body: some View {
        HStack(spacing: 10) {
            if item.tier == .safeAutoClean {
                Button {
                    vm.toggleCleanupSelection(item.id)
                } label: {
                    Image(systemName: vm.selectedCleanupIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundStyle(vm.selectedCleanupIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "folder.badge.questionmark")
                    .foregroundStyle(.purple)
                    .frame(width: 22, height: 22)
            }

            Image(systemName: itemIcon.name)
                .font(.system(size: 14))
                .foregroundStyle(itemIcon.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(safetyBadge.label)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(safetyBadge.color.opacity(0.12), in: Capsule())
                        .foregroundStyle(safetyBadge.color)
                }
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(Formatters.bytes(item.sizeBytes))
                .font(.caption.monospacedDigit().weight(.semibold))

            Button {
                let firstPath = item.path.split(separator: "|").first.map(String.init) ?? item.path
                vm.revealInFinder(firstPath)
            } label: {
                Image(systemName: "folder")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Mở thư mục trong Finder")
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
