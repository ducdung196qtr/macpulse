import SwiftUI
import MacPulseCore

struct CleanerView: View {
    @ObservedObject var vm: AppViewModel

    private var visibleFilter: CleanerFocusSection {
        vm.cleanerFocus
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter pills separating RAM vs Cache vs SSD Storage
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

                    summaryCards

                    chromeRescueCard

                    if visibleFilter == .all || visibleFilter == .ram {
                        ramSection
                    }

                    if visibleFilter == .all || visibleFilter == .cache {
                        cacheSection
                    }

                    if visibleFilter == .all || visibleFilter == .storage {
                        ssdStorageSection
                    }
                }
                .padding(14)
            }

            Divider()
            HStack {
                Button("Quét lại SSD") {
                    vm.scanCleanup()
                }
                .controlSize(.small)

                Spacer()

                Text("SSD đã chọn: \(Formatters.bytes(vm.totalSelectedCleanupBytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(vm.isCleaning ? "Đang dọn..." : "Dọn Cache/Log đã chọn") {
                    vm.runSelectedCleanup()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(vm.isCleaning || vm.totalSelectedCleanupBytes == 0)
            }
            .padding(12)
        }
    }

    private var cleanerFilterHeader: some View {
        HStack(spacing: 4) {
            filterButton("Tất cả", section: .all, icon: "square.grid.2x2")
            filterButton("RAM (Đang chạy)", section: .ram, icon: "memorychip")
            filterButton("Cache SSD", section: .cache, icon: "tray.full")
            filterButton("Bộ nhớ SSD", section: .storage, icon: "internaldrive")
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func filterButton(_ label: String, section: CleanerFocusSection, icon: String) -> some View {
        let active = vm.cleanerFocus == section
        return Button {
            vm.cleanerFocus = section
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption.weight(active ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(active ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summaryCards: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "memorychip")
                        .foregroundStyle(.purple)
                    Text("RAM (Bộ nhớ chạy)")
                        .font(.caption.weight(.bold))
                }
                if let mem = vm.snapshot?.memory {
                    Text(String(format: "Còn %.1f GB • Nén %.1f GB", mem.availableGB, mem.compressedGB))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
                Text("Đóng app/tab thừa để hết lag ngay")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(Color.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.green)
                    Text("SSD (Lưu trữ)")
                        .font(.caption.weight(.bold))
                }
                if let disk = vm.snapshot?.disk {
                    Text(String(format: "Trống %.1f GB • Cache %@", disk.availableGB, Formatters.bytes(vm.totalSafeCacheBytes)))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
                Text("Xoá Cache giúp trống ổ cứng, 0% mất dữ liệu")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        }
    }


    private var chromeRescueCard: some View {
        let chromeCacheSize = vm.cacheCandidates.first(where: { $0.id == "cache-chrome" })?.sizeBytes ?? 0
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

    private var ramSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "memorychip.fill")
                    .foregroundStyle(.purple)
                Text("1. Giải phóng RAM (Bộ nhớ đang chạy)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("Thu hồi tối đa ~\(Formatters.bytes(vm.estimatedReclaimableRAMBytes))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.purple)
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

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(.green)
                Text("2. Dọn Cache (Bộ nhớ đệm tạm trên SSD)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(Formatters.bytes(vm.totalSafeCacheBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.green)
            }

            Text("Tệp đệm trình duyệt & gói tải dev. Xoá hoàn toàn an toàn, ứng dụng tự tạo lại — KHÔNG làm mất mật khẩu, bookmark hay tài liệu.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if vm.cacheCandidates.isEmpty {
                Text("Không có cache lớn cần dọn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ForEach(vm.cacheCandidates) { item in
                    CleanupRowView(item: item, vm: vm)
                }
            }
        }
    }

    private var ssdStorageSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(.orange)
                Text("3. Bộ nhớ lưu trữ SSD (Log & Dữ liệu nặng)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(Formatters.bytes(vm.totalHeavyStorageBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Text("File log phình to (cắt rỗng an toàn) và dữ liệu/database công cụ dung lượng lớn (chỉ Mở Finder xem, MacPulse không tự ý xoá).")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(vm.logAndTrashCandidates) { item in
                CleanupRowView(item: item, vm: vm)
            }

            ForEach(vm.storageHeavyCandidates) { item in
                CleanupRowView(item: item, vm: vm)
            }

            if vm.logAndTrashCandidates.isEmpty && vm.storageHeavyCandidates.isEmpty {
                Text("Chưa thấy log phình to hay file runtime nào vượt ngưỡng 500 MB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }
}

private struct CleanupRowView: View {
    let item: CleanupCandidate
    @ObservedObject var vm: AppViewModel

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
                    .foregroundStyle(.orange)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(Formatters.bytes(item.sizeBytes))
                .font(.caption.monospacedDigit().weight(.semibold))

            if item.tier == .inspectOnly {
                Button("Mở Finder") {
                    vm.revealInFinder(item.path)
                }
                .controlSize(.mini)
            }
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
