import SwiftUI
import MacPulseCore

struct CleanerView: View {
    @ObservedObject var vm: AppViewModel
    @State private var isRescueManuallyExpanded: Bool = false

    private var visibleFilter: CleanerFocusSection {
        vm.cleanerFocus
    }

    private var hasActiveBrowserAlert: Bool {
        vm.orphanAutomationGroup != nil || !vm.stuckChromeRenderers.isEmpty
    }

    private var isRescueExpanded: Bool {
        hasActiveBrowserAlert || isRescueManuallyExpanded || visibleFilter == .browser
    }

    var body: some View {
        VStack(spacing: 0) {
            cleanerFilterHeader
                .padding(.horizontal, 14)
                .padding(.top, 7)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    if let pending = vm.pendingTerminationGroup {
                        InlineConfirmTerminationCard(group: pending, vm: vm)
                    }

                    if vm.showTabInspector {
                        BrowserTabsInspectorCard(vm: vm)
                    }

                    if let msg = vm.cleanupOutcomeMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(HudTheme.emerald)
                            Text(msg)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HudTheme.emerald)
                            Spacer()
                            Button {
                                vm.cleanupOutcomeMessage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(HudTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .hudCard(accent: HudTheme.emerald, chamfer: 7, padding: 9)
                    }

                    heroSummaryCard

                    if visibleFilter == .all || visibleFilter == .browser {
                        chromeRescueCard
                    }

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

            Rectangle()
                .fill(LinearGradient(colors: [.clear, HudTheme.cyan.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)
            cleanerFooterBar
        }
    }

    // MARK: - Filter Bar
    private var cleanerFilterHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
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
        .background(HudTheme.insetBg, in: ChamferedRect(cut: 6, cornerRadius: 3))
        .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(HudTheme.cyan.opacity(0.22), lineWidth: 0.75))
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
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(active ? HudTheme.cyan : HudTheme.textMuted)
                Text(label)
                    .font(.system(size: 10.5, weight: active ? .bold : .medium))
                    .foregroundStyle(active ? HudTheme.textPrimary : HudTheme.textSecondary)
                if countText != "0 B" && countText != "0.0 B" {
                    Text(countText)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(active ? HudTheme.cyan.opacity(0.24) : HudTheme.cardBg, in: Capsule())
                        .foregroundStyle(active ? HudTheme.cyan : HudTheme.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(active ? HudTheme.cyan.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(active ? HudTheme.cyan.opacity(0.55) : .clear, lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero Telemetry Summary
    private var heroSummaryCard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(HudTheme.violet)
                        Text("RÁC AN TOÀN SSD")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(HudTheme.textSecondary)
                        Spacer()
                        if vm.isScanningCleanup {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    Text(Formatters.bytes(vm.totalSafeCacheBytes))
                        .font(.system(size: 19, weight: .black, design: .monospaced))
                        .foregroundStyle(HudTheme.violet)
                    Text("Cache AI, trình duyệt & build — 0% mất code/tài khoản")
                        .font(.system(size: 9.5))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudCard(accent: HudTheme.violet, chamfer: 9, padding: 10, showBrackets: true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(HudTheme.cyan)
                        Text("RAM KHẢ DỤNG")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(HudTheme.textSecondary)
                    }
                    if let mem = vm.snapshot?.memory {
                        Text(String(format: "%.1f GB TRỐNG", mem.availableGB))
                            .font(.system(size: 19, weight: .black, design: .monospaced))
                            .foregroundStyle(HudTheme.cyan)
                        SegmentedMemoryBar(memory: mem, height: 4.5)
                    }
                    Text("Thu hồi ~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes)) từ app thừa")
                        .font(.system(size: 9.5))
                        .foregroundStyle(HudTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudCard(accent: HudTheme.cyan, chamfer: 9, padding: 10, showBrackets: true)
            }

            HStack(spacing: 7) {
                HudButton(title: "Chọn tất cả an toàn", color: HudTheme.cyan, filled: false, compact: true) {
                    vm.selectAllSafe()
                }
                HudButton(title: "Bỏ chọn", color: HudTheme.textSecondary, filled: false, compact: true) {
                    vm.deselectAll()
                }

                Spacer()

                if vm.totalSelectedCleanupBytes > 0 {
                    HudButton(
                        title: vm.isCleaning ? "Đang dọn..." : "Dọn ngay (\(Formatters.bytes(vm.totalSelectedCleanupBytes)))",
                        icon: "trash.slash.fill",
                        color: HudTheme.emerald,
                        filled: true,
                        compact: false,
                        disabled: vm.isCleaning
                    ) {
                        vm.runSelectedCleanup()
                    }
                }
            }
        }
    }

    // MARK: - Smart Collapsible Chrome & Automation Rescue Hub
    private var chromeRescueCard: some View {
        let chromeCacheSize = vm.browserCandidates.first(where: { $0.id == "cache-chrome" })?.sizeBytes ?? 0
        let stuckCount = vm.stuckChromeRenderers.count
        let totalStuckCPU = vm.stuckChromeRenderers.reduce(0.0) { $0 + $1.cpuPercent }
        let totalChromeProcs = vm.processGroups.first(where: { $0.id == "app:Google Chrome" })?.processCount ?? 0
        let autoGroup = vm.orphanAutomationGroup
        let cardAccent: Color = hasActiveBrowserAlert ? HudTheme.amber : HudTheme.cyan

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRescueManuallyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        ChamferedRect(cut: 6, cornerRadius: 3)
                            .fill(cardAccent.opacity(0.20))
                            .overlay(ChamferedRect(cut: 6, cornerRadius: 3).strokeBorder(cardAccent.opacity(0.6), lineWidth: 0.8))
                            .frame(width: 30, height: 30)
                        Image(systemName: hasActiveBrowserAlert ? "exclamationmark.shield.fill" : "lifepreserver.fill")
                            .foregroundStyle(cardAccent)
                            .font(.system(size: 14, weight: .bold))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("CHROME & AUTOMATION RESCUE")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.textPrimary)
                            if let auto = autoGroup {
                                Text("\(auto.processCount) BOT NGẦM")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(HudTheme.amber.opacity(0.22), in: Capsule())
                                    .foregroundStyle(HudTheme.amber)
                            } else if stuckCount > 0 {
                                Text("\(stuckCount) TAB ĐƠ")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(HudTheme.amber.opacity(0.22), in: Capsule())
                                    .foregroundStyle(HudTheme.amber)
                            } else {
                                Text("NOMINAL")
                                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(HudTheme.emerald.opacity(0.18), in: Capsule())
                                    .foregroundStyle(HudTheme.emerald)
                            }
                        }
                        Text(hasActiveBrowserAlert
                             ? "Phát hiện tác vụ trình duyệt hoặc cụm headless ngầm ngốn tải — bấm xử lý tức thì."
                             : "Gỡ đơ tab localhost, khởi động lại sạch Chrome, hoặc reset cụm agent-browser.")
                            .font(.system(size: 10))
                            .foregroundStyle(HudTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if chromeCacheSize > 0 {
                        Text(Formatters.bytes(chromeCacheSize))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(HudTheme.cyan)
                    }

                    Image(systemName: isRescueExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(cardAccent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isRescueExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(HudTheme.emerald)
                        .font(.caption)
                    Text("Cô lập tuyệt đối: Không mất Extension, không mất tab/cookie, gỡ đơ Chrome thường không chạm bot ngầm.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HudTheme.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HudTheme.emerald.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HudTheme.emerald.opacity(0.32), lineWidth: 0.7))

                // Action 1: Stuck Renderers
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: stuckCount > 0 ? "exclamationmark.triangle.fill" : "bolt.horizontal.fill")
                            .foregroundStyle(stuckCount > 0 ? HudTheme.amber : HudTheme.cyan)
                        Text("Gỡ đơ tab/task Chrome thường (Localhost / Dev Server)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HudTheme.textPrimary)
                        Spacer()
                        if stuckCount > 0 {
                            Text("\(stuckCount) TAB • \(String(format: "%.0f%%", totalStuckCPU)) CPU")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.amber)
                        }
                    }

                    Text("Chỉ dừng tiến trình render tab đang treo trên Chrome thường (hiện Aw Snap để F5). Giữ nguyên toàn bộ cửa sổ khác, Extension và bot headless.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        HudButton(
                            title: stuckCount > 0 ? "Gỡ kẹt ngay (\(stuckCount) tab)" : "Kiểm tra & Gỡ tab đơ",
                            icon: "bolt.fill",
                            color: stuckCount > 0 ? HudTheme.amber : HudTheme.cyan,
                            filled: true,
                            compact: true
                        ) {
                            vm.killStuckChromeRenderers(forceAll: false)
                        }

                        if totalChromeProcs > 0 {
                            HudButton(title: "Gỡ tất cả renderer", color: HudTheme.textSecondary, filled: false, compact: true) {
                                vm.killStuckChromeRenderers(forceAll: true)
                            }
                        }
                    }
                }
                .padding(9)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(stuckCount > 0 ? HudTheme.amber.opacity(0.48) : HudTheme.cyan.opacity(0.20), lineWidth: 0.8))

                // Action 2: Full Clean Restart
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(HudTheme.cobalt)
                        Text("Khởi động lại sạch Chrome (Đóng êm 2.4s • Gỡ lock • Dọn cache)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HudTheme.textPrimary)
                    }

                    Text("Đóng nhẹ nhàng để lưu trọn phiên tab, gỡ sạch SingletonLock & DevToolsActivePort, dọn OS cache tạm và mở lại Chrome mượt mà.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        HudButton(
                            title: vm.isRescuingChrome ? "Đang cứu Chrome..." : "Khởi động lại sạch Chrome",
                            icon: "arrow.clockwise",
                            color: HudTheme.cobalt,
                            filled: true,
                            compact: true,
                            disabled: vm.isRescuingChrome || vm.isCleaning
                        ) {
                            vm.rescueAndCleanChrome(relaunch: true)
                        }

                        HudButton(
                            title: "Chỉ tắt & dọn lock",
                            color: HudTheme.textSecondary,
                            filled: false,
                            compact: true,
                            disabled: vm.isRescuingChrome || vm.isCleaning
                        ) {
                            vm.rescueAndCleanChrome(relaunch: false)
                        }
                    }
                }
                .padding(9)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HudTheme.cobalt.opacity(0.25), lineWidth: 0.8))

                // Action 3: Automation & agent-browser Rescue
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: autoGroup != nil ? "exclamationmark.octagon.fill" : "terminal.fill")
                            .foregroundStyle(autoGroup != nil ? HudTheme.amber : HudTheme.textSecondary)
                        Text("Dừng & Reset Chrome Automation (agent-browser / MCP)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HudTheme.textPrimary)
                        Spacer()
                        if let auto = autoGroup {
                            Text("\(auto.processCount) PROC • \(String(format: "%.0f%%", auto.totalCPUPercent)) CPU • \(Formatters.bytes(auto.totalRSSBytes))")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(HudTheme.amber)
                        }
                    }

                    Text(autoGroup != nil
                        ? "Cụm headless Chrome & agent-browser đang chạy ngầm ngốn tài nguyên. Dừng sạch và gỡ khoá profile tự động mà không đụng Chrome thường."
                        : "Dừng mọi tiến trình Chrome headless / agent-browser ngầm và xoá sạch SingletonLock / DevToolsActivePort.")
                        .font(.caption2)
                        .foregroundStyle(HudTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HudButton(
                        title: autoGroup != nil ? "Dừng & Reset sạch cụm Automation" : "Reset sạch Chrome Automation",
                        icon: "arrow.counterclockwise.circle.fill",
                        color: autoGroup != nil ? HudTheme.amber : HudTheme.cyan,
                        filled: autoGroup != nil,
                        compact: true,
                        disabled: vm.isRescuingChrome || vm.isCleaning
                    ) {
                        vm.resetBrowserAutomation()
                    }
                }
                .padding(9)
                .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(autoGroup != nil ? HudTheme.amber.opacity(0.55) : HudTheme.cyan.opacity(0.20), lineWidth: 0.8))
            }
        }
        .hudCard(accent: cardAccent, chamfer: 10, padding: 11, showBrackets: true)
    }

    // MARK: - Category Sections
    private var aiSection: some View {
        cleanupSectionBlock(
            icon: "sparkles",
            title: "Rác AI (Antigravity, OpenMausBot, Cursor, Codex, Claude)",
            subtitle: "Cache cập nhật ShipIt, logs, bộ đệm GPU/Shader tạm của công cụ AI — 0% mất API key, prompt hay cookie.",
            color: HudTheme.violet,
            totalBytes: vm.totalAIGarbageBytes,
            items: vm.aiCandidates,
            emptyMessage: "Không phát hiện tệp rác AI nào đáng kể."
        )
    }

    private var browserSection: some View {
        cleanupSectionBlock(
            icon: "globe",
            title: "Cache Trình duyệt (Chrome, Brave, Edge, Safari, Arc, Firefox)",
            subtitle: "Chỉ xoá OS Cache tạm (~/Library/Caches). Bảo vệ tuyệt đối 100% Extension, tab, bookmark và tài khoản.",
            color: HudTheme.cyan,
            totalBytes: vm.totalBrowserCacheBytes,
            items: vm.browserCandidates,
            emptyMessage: "Không có cache trình duyệt lớn cần dọn."
        )
    }

    private var developerSection: some View {
        cleanupSectionBlock(
            icon: "hammer.fill",
            title: "Cache Lập trình & Build (Xcode, npm, Homebrew, pip, Composer)",
            subtitle: "Gói tải về và tệp trung gian build — tự tải lại tự động khi bạn chạy build hoặc install.",
            color: HudTheme.amber,
            totalBytes: vm.totalDeveloperBuildBytes,
            items: vm.developerCandidates,
            emptyMessage: "Không có cache lập trình nào cần dọn."
        )
    }

    private var logsSection: some View {
        cleanupSectionBlock(
            icon: "doc.text.fill",
            title: "File Log phình to & Thùng rác",
            subtitle: "Cắt rỗng an toàn log LocalWP lớn, dọn thumbnail QuickLook và Thùng rác (tắt mặc định).",
            color: HudTheme.amber,
            totalBytes: vm.totalLogsAndTrashBytes,
            items: vm.logAndTrashCandidates,
            emptyMessage: "Không có file log phình to hay rác hệ thống."
        )
    }

    private var storageHeavySection: some View {
        cleanupSectionBlock(
            icon: "internaldrive.fill",
            title: "Dữ liệu dung lượng lớn (Chỉ xem Finder)",
            subtitle: "Database, trình duyệt Playwright/Puppeteer hoặc lịch sử phiên AI — MacPulse KHÔNG tự ý xoá.",
            color: HudTheme.cobalt,
            totalBytes: vm.totalHeavyStorageBytes,
            items: vm.storageHeavyCandidates,
            emptyMessage: "Không phát hiện dữ liệu dung lượng lớn (>500 MB) cần kiểm tra."
        )
    }

    private func cleanupSectionBlock(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        totalBytes: UInt64,
        items: [CleanupCandidate],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(
                icon: icon,
                title: title,
                color: color,
                trailingText: Formatters.bytes(totalBytes)
            )
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(HudTheme.textSecondary)

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(HudTheme.textMuted)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 7))
            } else {
                LazyVStack(spacing: 5) {
                    ForEach(items) { item in
                        CleanupRowView(item: item, vm: vm, maxSizeBytes: vm.maxCandidateSizeBytes)
                    }
                }
            }
        }
    }

    private var ramSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionEyebrow(
                icon: "memorychip.fill",
                title: "Giải phóng RAM thực (Ứng dụng đang chạy)",
                color: HudTheme.cyan,
                trailingText: "~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes))"
            )

            Text("Đóng chọn lọc ứng dụng rảnh hoặc tab trùng để giải phóng RAM thật, không dùng lệnh ảo gây khựng hệ thống.")
                .font(.system(size: 10))
                .foregroundStyle(HudTheme.textSecondary)

            HStack(spacing: 8) {
                HudButton(title: "Soi & đóng từng tab", icon: "macwindow", color: HudTheme.cyan, filled: false, compact: true) {
                    vm.scanBrowserTabs()
                }

                if let orphan = vm.orphanAutomationGroup {
                    HudButton(title: "Dừng & Reset Bot (\(Formatters.bytes(orphan.totalRSSBytes)))", color: HudTheme.amber, filled: true, compact: true) {
                        vm.resetBrowserAutomation()
                    }
                }
            }

            LazyVStack(spacing: 5) {
                ForEach(vm.ramReclaimableGroups) { group in
                    ProcessRowView(group: group, vm: vm, highlightRAM: true)
                }
            }
        }
    }

    // MARK: - Footer
    private var cleanerFooterBar: some View {
        HStack {
            HudButton(
                title: vm.isScanningCleanup ? "Đang quét..." : "Quét lại SSD",
                icon: "arrow.clockwise",
                color: HudTheme.cyan,
                filled: false,
                compact: true,
                disabled: vm.isScanningCleanup
            ) {
                vm.scanCleanup()
            }

            Spacer()

            Text("ĐÃ CHỌN: \(Formatters.bytes(vm.totalSelectedCleanupBytes).uppercased())")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(HudTheme.textSecondary)

            HudButton(
                title: vm.isCleaning ? "Đang dọn..." : "Dọn rác đã chọn",
                icon: "sparkles",
                color: HudTheme.emerald,
                filled: true,
                compact: true,
                disabled: vm.isCleaning || vm.totalSelectedCleanupBytes == 0
            ) {
                vm.runSelectedCleanup()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8.5)
        .background(HudTheme.bgDeep.opacity(0.65))
    }
}

// MARK: - Cleanup Row with Glowing Relative Size Bar
private struct CleanupRowView: View {
    let item: CleanupCandidate
    @ObservedObject var vm: AppViewModel
    let maxSizeBytes: UInt64

    private var itemIcon: (name: String, color: Color) {
        let id = item.id.lowercased()
        if id.contains("openmaus") { return ("cpu", HudTheme.amber) }
        if id.contains("ai") || id.contains("cursor") || id.contains("codex") || id.contains("claude") || id.contains("gemini") {
            return ("sparkles", HudTheme.violet)
        }
        if id.contains("chrome") { return ("globe", HudTheme.cyan) }
        if id.contains("brave") { return ("shield.lefthalf.filled", HudTheme.amber) }
        if id.contains("firefox") { return ("flame.fill", HudTheme.amber) }
        if id.contains("safari") { return ("safari", HudTheme.cyan) }
        if id.contains("edge") { return ("globe.americas.fill", HudTheme.teal) }
        if id.contains("arc") { return ("globe.europe.africa.fill", HudTheme.cobalt) }
        if id.contains("vscode") { return ("chevron.left.forwardslash.chevron.right", HudTheme.cyan) }
        if id.contains("brew") || id.contains("homebrew") { return ("cup.and.saucer.fill", HudTheme.amber) }
        if id.contains("npm") || id.contains("yarn") || id.contains("pnpm") || id.contains("composer") { return ("shippingbox.fill", HudTheme.crimson) }
        if id.contains("swiftpm") || id.contains("xcode") { return ("hammer.fill", HudTheme.amber) }
        if id.contains("pip") || id.contains("uv") || id.contains("python") { return ("terminal.fill", HudTheme.cobalt) }
        if id.contains("trash") { return ("trash.fill", HudTheme.crimson) }
        if id.contains("log") { return ("doc.text.fill", HudTheme.amber) }
        if id.contains("db") || id.contains("brain") { return ("cylinder.split.1x2.fill", HudTheme.violet) }
        if id.contains("playwright") || id.contains("puppeteer") { return ("globe.badge.chevron.backward", HudTheme.cobalt) }
        if id.contains("quicklook") { return ("eye.fill", HudTheme.teal) }
        return ("tray.full.fill", HudTheme.emerald)
    }

    private var safetyBadge: (label: String, color: Color) {
        if item.tier == .inspectOnly { return ("CHỈ XEM", HudTheme.cobalt) }
        if item.defaultSelected { return ("AN TOÀN 100%", HudTheme.emerald) }
        return ("TỰ CHỌN", HudTheme.amber)
    }

    private var sizeRatio: Double {
        max(0.04, min(1.0, Double(item.sizeBytes) / Double(max(1, maxSizeBytes))))
    }

    var body: some View {
        let isSelected = vm.selectedCleanupIDs.contains(item.id)
        return HStack(spacing: 9) {
            if item.tier == .safeAutoClean {
                Button {
                    vm.toggleCleanupSelection(item.id)
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15.5))
                        .foregroundStyle(isSelected ? HudTheme.cyan : HudTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "folder.badge.questionmark")
                    .foregroundStyle(HudTheme.cobalt)
                    .frame(width: 20, height: 20)
            }

            Image(systemName: itemIcon.name)
                .font(.system(size: 13))
                .foregroundStyle(itemIcon.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(HudTheme.textPrimary)
                        .lineLimit(1)
                    Text(safetyBadge.label)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(safetyBadge.color.opacity(0.16), in: Capsule())
                        .foregroundStyle(safetyBadge.color)
                }
                Text(item.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(HudTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.bytes(item.sizeBytes))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(HudTheme.textPrimary)
                ZStack(alignment: .leading) {
                    Capsule().fill(HudTheme.insetBg)
                    Capsule()
                        .fill(itemIcon.color)
                        .frame(width: max(3, 46 * CGFloat(sizeRatio)))
                }
                .frame(width: 46, height: 3)
            }

            Button {
                let firstPath = item.path.split(separator: "|").first.map(String.init) ?? item.path
                vm.revealInFinder(firstPath)
            } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(HudTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(HudTheme.insetBg, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Mở thư mục trong Finder")
        }
        .hudCard(accent: isSelected ? HudTheme.cyan.opacity(0.55) : HudTheme.textMuted.opacity(0.28), chamfer: 6, padding: 8.5)
    }
}
