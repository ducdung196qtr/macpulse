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
                .padding(.top, 8)
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
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(PulseTheme.emerald)
                            Text(msg)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(PulseTheme.emerald)
                            Spacer()
                            Button {
                                vm.cleanupOutcomeMessage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .telemetryCard(accent: PulseTheme.emerald, cornerRadius: 9, padding: 9)
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

            Divider().opacity(0.45)
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
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                if countText != "0 B" && countText != "0.0 B" {
                    Text(countText)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(active ? Color.white.opacity(0.24) : Color.primary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(active ? PulseTheme.cobalt : Color.clear, in: RoundedRectangle(cornerRadius: 6.5))
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.85))
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
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PulseTheme.violet)
                        Text("RÁC AN TOÀN SSD")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if vm.isScanningCleanup {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    Text(Formatters.bytes(vm.totalSafeCacheBytes))
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(PulseTheme.violet)
                    Text("Cache AI, trình duyệt & build — 0% mất code/tài khoản")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .telemetryCard(accent: PulseTheme.violet, cornerRadius: 10, padding: 10)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PulseTheme.cyan)
                        Text("RAM KHẢ DỤNG")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                    }
                    if let mem = vm.snapshot?.memory {
                        Text(String(format: "%.1f GB trống", mem.availableGB))
                            .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(PulseTheme.cyan)
                        SegmentedMemoryBar(memory: mem, height: 4)
                    }
                    Text("Thu hồi ~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes)) từ app thừa")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .telemetryCard(accent: PulseTheme.cyan, cornerRadius: 10, padding: 10)
            }

            HStack {
                HStack(spacing: 6) {
                    Button("Chọn tất cả an toàn") { vm.selectAllSafe() }
                        .controlSize(.mini)
                    Button("Bỏ chọn") { vm.deselectAll() }
                        .controlSize(.mini)
                }

                Spacer()

                if vm.totalSelectedCleanupBytes > 0 {
                    Button(vm.isCleaning ? "Đang dọn..." : "Dọn ngay (\(Formatters.bytes(vm.totalSelectedCleanupBytes)))") {
                        vm.runSelectedCleanup()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.emerald)
                    .controlSize(.small)
                    .disabled(vm.isCleaning)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Smart Collapsible Chrome & Automation Rescue Hub
    private var chromeRescueCard: some View {
        let chromeCacheSize = vm.browserCandidates.first(where: { $0.id == "cache-chrome" })?.sizeBytes ?? 0
        let stuckCount = vm.stuckChromeRenderers.count
        let totalStuckCPU = vm.stuckChromeRenderers.reduce(0.0) { $0 + $1.cpuPercent }
        let totalChromeProcs = vm.processGroups.first(where: { $0.id == "app:Google Chrome" })?.processCount ?? 0
        let autoGroup = vm.orphanAutomationGroup
        let cardAccent: Color = hasActiveBrowserAlert ? PulseTheme.amber : PulseTheme.cyan

        return VStack(alignment: .leading, spacing: 10) {
            // Clickable Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRescueManuallyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(cardAccent.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: hasActiveBrowserAlert ? "exclamationmark.shield.fill" : "lifepreserver.fill")
                            .foregroundStyle(cardAccent)
                            .font(.system(size: 14, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("Cứu hộ Chrome & Automation")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(.primary)
                            if let auto = autoGroup {
                                Text("\(auto.processCount) bot ngầm")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(PulseTheme.amber.opacity(0.2), in: Capsule())
                                    .foregroundStyle(PulseTheme.amber)
                            } else if stuckCount > 0 {
                                Text("\(stuckCount) tab đơ")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(PulseTheme.amber.opacity(0.2), in: Capsule())
                                    .foregroundStyle(PulseTheme.amber)
                            } else {
                                Text("ỔN ĐỊNH")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(PulseTheme.emerald.opacity(0.16), in: Capsule())
                                    .foregroundStyle(PulseTheme.emerald)
                            }
                        }
                        Text(hasActiveBrowserAlert
                             ? "Phát hiện tác vụ trình duyệt hoặc cụm headless ngầm ngốn tải — bấm để xử lý tức thì."
                             : "Gỡ đơ tab localhost, khởi động lại sạch Chrome, hoặc reset cụm agent-browser (0% mất Extension).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if chromeCacheSize > 0 {
                        Text(Formatters.bytes(chromeCacheSize))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PulseTheme.cyan)
                    }

                    Image(systemName: isRescueExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isRescueExpanded {
                // Safety badge
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(PulseTheme.emerald)
                        .font(.caption)
                    Text("Cô lập tuyệt đối: Không mất Extension, không mất tab/cookie, gỡ đơ Chrome thường không chạm bot ngầm và ngược lại.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseTheme.emerald.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))

                // Action 1: Stuck Renderers (Normal GUI Chrome ONLY)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: stuckCount > 0 ? "exclamationmark.triangle.fill" : "bolt.horizontal.fill")
                            .foregroundStyle(stuckCount > 0 ? PulseTheme.amber : .secondary)
                        Text("Gỡ đơ tab/task Chrome thường (Localhost / Dev Server)")
                            .font(.caption.weight(.bold))
                        Spacer()
                        if stuckCount > 0 {
                            Text("\(stuckCount) tab • \(String(format: "%.0f%%", totalStuckCPU)) CPU")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(PulseTheme.amber)
                        }
                    }

                    Text("Chỉ dừng tiến trình render tab đang treo trên Chrome thường (hiện Aw Snap để F5). Toàn bộ cửa sổ khác, Extension và bot headless không bị ảnh hưởng.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            vm.killStuckChromeRenderers(forceAll: false)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                Text(stuckCount > 0 ? "Gỡ kẹt ngay (\(stuckCount) tab)" : "Kiểm tra & Gỡ tab đơ")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(stuckCount > 0 ? PulseTheme.amber : PulseTheme.cyan)
                        .controlSize(.small)

                        if totalChromeProcs > 0 {
                            Button("Gỡ tất cả renderer") {
                                vm.killStuckChromeRenderers(forceAll: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(9)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stuckCount > 0 ? PulseTheme.amber.opacity(0.38) : Color.primary.opacity(0.08), lineWidth: 0.8))

                // Action 2: Full Clean Restart
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(PulseTheme.cyan)
                        Text("Khởi động lại sạch Chrome (Đóng êm 2.4s • Gỡ lock • Dọn cache)")
                            .font(.caption.weight(.bold))
                    }

                    Text("Đóng nhẹ nhàng để lưu trọn phiên tab, gỡ sạch SingletonLock & DevToolsActivePort, dọn OS cache tạm và tự mở lại Chrome mượt mà.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button(vm.isRescuingChrome ? "Đang cứu Chrome..." : "Khởi động lại sạch Chrome") {
                            vm.rescueAndCleanChrome(relaunch: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PulseTheme.cobalt)
                        .controlSize(.small)
                        .disabled(vm.isRescuingChrome || vm.isCleaning)

                        Button("Chỉ tắt & dọn lock") {
                            vm.rescueAndCleanChrome(relaunch: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(vm.isRescuingChrome || vm.isCleaning)
                    }
                }
                .padding(9)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))

                // Action 3: Automation & agent-browser Rescue
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: autoGroup != nil ? "exclamationmark.octagon.fill" : "terminal.fill")
                            .foregroundStyle(autoGroup != nil ? PulseTheme.amber : .secondary)
                        Text("Dừng & Reset Chrome Automation (agent-browser / MCP)")
                            .font(.caption.weight(.bold))
                        Spacer()
                        if let auto = autoGroup {
                            Text("\(auto.processCount) tiến trình • \(String(format: "%.0f%%", auto.totalCPUPercent)) CPU • \(Formatters.bytes(auto.totalRSSBytes))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(PulseTheme.amber)
                        }
                    }

                    Text(autoGroup != nil
                        ? "Cụm headless Chrome & agent-browser đang chạy ngầm ngốn tài nguyên. Dừng sạch và gỡ khoá profile tự động mà không đụng Chrome thường."
                        : "Dừng mọi tiến trình Chrome headless / agent-browser ngầm và xoá sạch SingletonLock / DevToolsActivePort.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        vm.resetBrowserAutomation()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                            Text(autoGroup != nil ? "Dừng & Reset sạch cụm Automation" : "Reset sạch Chrome Automation")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(autoGroup != nil ? PulseTheme.amber : .secondary)
                    .controlSize(.small)
                    .disabled(vm.isRescuingChrome || vm.isCleaning)
                }
                .padding(9)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(autoGroup != nil ? PulseTheme.amber.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 0.8))
            }
        }
        .telemetryCard(accent: cardAccent, cornerRadius: 11, padding: 11)
    }

    // MARK: - Category Sections
    private var aiSection: some View {
        cleanupSectionBlock(
            icon: "sparkles",
            title: "Rác AI (Antigravity, OpenMausBot, Cursor, Codex, Claude)",
            subtitle: "Cache cập nhật ShipIt, logs, bộ đệm GPU/Shader tạm của công cụ AI — 0% mất API key, prompt hay cookie.",
            color: PulseTheme.violet,
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
            color: PulseTheme.cyan,
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
            color: PulseTheme.amber,
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
            color: PulseTheme.amber,
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
            color: PulseTheme.cobalt,
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
                .font(.caption2)
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 5) {
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
                color: PulseTheme.cyan,
                trailingText: "Tối đa ~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes))"
            )

            Text("Đóng chọn lọc ứng dụng rảnh hoặc tab trùng để giải phóng RAM thật, không dùng lệnh ảo gây khựng hệ thống.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Soi & đóng từng tab trình duyệt") {
                    vm.scanBrowserTabs()
                }
                .controlSize(.small)

                if let orphan = vm.orphanAutomationGroup {
                    Button("Dừng & Reset Bot (\(Formatters.bytes(orphan.totalRSSBytes)))") {
                        vm.resetBrowserAutomation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.amber)
                    .controlSize(.small)
                }
            }

            VStack(spacing: 5) {
                ForEach(vm.ramReclaimableGroups) { group in
                    ProcessRowView(group: group, vm: vm, highlightRAM: true)
                }
            }
        }
    }

    // MARK: - Footer
    private var cleanerFooterBar: some View {
        HStack {
            Button {
                vm.scanCleanup()
            } label: {
                HStack(spacing: 4) {
                    if vm.isScanningCleanup {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.bold())
                    }
                    Text(vm.isScanningCleanup ? "Đang quét SSD..." : "Quét lại SSD")
                }
            }
            .controlSize(.small)
            .disabled(vm.isScanningCleanup)

            Spacer()

            Text("Đã chọn: \(Formatters.bytes(vm.totalSelectedCleanupBytes))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            Button(vm.isCleaning ? "Đang dọn..." : "Dọn rác đã chọn") {
                vm.runSelectedCleanup()
            }
            .buttonStyle(.borderedProminent)
            .tint(PulseTheme.emerald)
            .controlSize(.small)
            .disabled(vm.isCleaning || vm.totalSelectedCleanupBytes == 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Cleanup Row with Relative Size Telemetry Bar
private struct CleanupRowView: View {
    let item: CleanupCandidate
    @ObservedObject var vm: AppViewModel
    let maxSizeBytes: UInt64

    private var itemIcon: (name: String, color: Color) {
        let id = item.id.lowercased()
        if id.contains("openmaus") { return ("cpu", PulseTheme.amber) }
        if id.contains("ai") || id.contains("cursor") || id.contains("codex") || id.contains("claude") || id.contains("gemini") {
            return ("sparkles", PulseTheme.violet)
        }
        if id.contains("chrome") { return ("globe", PulseTheme.cyan) }
        if id.contains("brave") { return ("shield.lefthalf.filled", PulseTheme.amber) }
        if id.contains("firefox") { return ("flame.fill", PulseTheme.amber) }
        if id.contains("safari") { return ("safari", PulseTheme.cyan) }
        if id.contains("edge") { return ("globe.americas.fill", PulseTheme.teal) }
        if id.contains("arc") { return ("globe.europe.africa.fill", PulseTheme.cobalt) }
        if id.contains("vscode") { return ("chevron.left.forwardslash.chevron.right", PulseTheme.cyan) }
        if id.contains("brew") || id.contains("homebrew") { return ("cup.and.saucer.fill", PulseTheme.amber) }
        if id.contains("npm") || id.contains("yarn") || id.contains("pnpm") || id.contains("composer") { return ("shippingbox.fill", PulseTheme.crimson) }
        if id.contains("swiftpm") || id.contains("xcode") { return ("hammer.fill", PulseTheme.amber) }
        if id.contains("pip") || id.contains("uv") || id.contains("python") { return ("terminal.fill", PulseTheme.cobalt) }
        if id.contains("trash") { return ("trash.fill", PulseTheme.crimson) }
        if id.contains("log") { return ("doc.text.fill", PulseTheme.amber) }
        if id.contains("db") || id.contains("brain") { return ("cylinder.split.1x2.fill", PulseTheme.violet) }
        if id.contains("playwright") || id.contains("puppeteer") { return ("globe.badge.chevron.backward", PulseTheme.cobalt) }
        if id.contains("quicklook") { return ("eye.fill", PulseTheme.teal) }
        return ("tray.full.fill", PulseTheme.emerald)
    }

    private var safetyBadge: (label: String, color: Color) {
        if item.tier == .inspectOnly { return ("Chỉ kiểm tra", PulseTheme.cobalt) }
        if item.defaultSelected { return ("An toàn 100%", PulseTheme.emerald) }
        return ("Tự chọn", PulseTheme.amber)
    }

    private var sizeRatio: Double {
        max(0.03, min(1.0, Double(item.sizeBytes) / Double(max(1, maxSizeBytes))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                if item.tier == .safeAutoClean {
                    Button {
                        vm.toggleCleanupSelection(item.id)
                    } label: {
                        Image(systemName: vm.selectedCleanupIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15.5))
                            .foregroundStyle(vm.selectedCleanupIDs.contains(item.id) ? PulseTheme.cyan : .secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundStyle(PulseTheme.cobalt)
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
                            .lineLimit(1)
                        Text(safetyBadge.label)
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(safetyBadge.color.opacity(0.14), in: Capsule())
                            .foregroundStyle(safetyBadge.color)
                    }
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Formatters.bytes(item.sizeBytes))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(itemIcon.color.opacity(0.85))
                            .frame(width: max(3, 46 * CGFloat(sizeRatio)))
                    }
                    .frame(width: 46, height: 3)
                }

                Button {
                    let firstPath = item.path.split(separator: "|").first.map(String.init) ?? item.path
                    vm.revealInFinder(firstPath)
                } label: {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Mở thư mục trong Finder")
            }
        }
        .telemetryCard(cornerRadius: 9, padding: 8.5)
    }
}
