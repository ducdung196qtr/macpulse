import Foundation

public enum HealthAnalyzer {
    public static func analyze(snapshot: SystemSnapshot, processGroups: [ProcessGroupSummary]) -> HealthReport {
        var score = 100
        var findings: [DiagnosticFinding] = []

        if let replayd = processGroups.first(where: { $0.id == "sys:replayd" }), replayd.totalCPUPercent >= 25.0 {
            let isSevere = replayd.totalCPUPercent >= 70.0
            score -= isSevere ? 25 : 12
            let culprit = processGroups.first {
                $0.id.contains("ChatGPT") || $0.id.contains("Codex") || $0.isOrphanAutomation || ($0.id == "app:Google Chrome" && $0.totalCPUPercent >= 15)
            }
            let callers = processGroups
                .filter { $0.id.contains("ChatGPT") || $0.id.contains("Codex") || $0.isOrphanAutomation || ($0.id == "app:Google Chrome" && $0.totalCPUPercent >= 15) }
                .map { "\($0.displayName) (\(Int($0.totalCPUPercent))% CPU)" }
            let callerHint = callers.isEmpty ? "Kiểm tra app ghi/đọc màn hình hoặc trình duyệt." : "Tác nhân khả nghi: \(callers.joined(separator: ", "))."

            let recAction: ProcessActionKind
            let targetID: String?
            let label: String?
            if let c = culprit, c.isOrphanAutomation {
                recAction = .killOrphanPuppeteer
                targetID = c.id
                label = "Dọn Puppeteer"
            } else if let c = culprit, c.actionKind == .quitAppGracefully {
                recAction = .quitAppGracefully
                targetID = c.id
                label = "Đóng \(c.displayName)"
            } else {
                recAction = .none
                targetID = nil
                label = nil
            }

            findings.append(DiagnosticFinding(
                id: "replayd-storm",
                severity: isSevere ? .critical : .warning,
                title: "Bão XPC replayd (\(Int(replayd.totalCPUPercent))% CPU)",
                detail: "Daemon ScreenCapture của macOS đang nhận kết nối lặp liên tục. \(callerHint)",
                recommendedAction: recAction,
                targetID: targetID,
                safetyLevel: culprit?.guidance.safetyLevel ?? .systemProtected,
                impactNote: "Không tắt trực tiếp replayd (hệ thống tự bật lại). Hãy đóng ứng dụng đang gọi chụp màn hình để replayd tự hạ tải.",
                actionLabel: label
            ))
        }

        if let orphan = processGroups.first(where: { $0.isOrphanAutomation }) {
            score -= 15
            findings.append(DiagnosticFinding(
                id: "orphan-puppeteer",
                severity: .warning,
                title: "Chrome automation chạy ngầm (\(Formatters.bytes(orphan.totalRSSBytes)))",
                detail: "Tiến trình Chrome headless/automation (Playwright/Puppeteer/MCP) đang chạy ngầm (\(Int(orphan.totalCPUPercent))% CPU) và có thể chặn mở Chrome.",
                recommendedAction: .killOrphanPuppeteer,
                targetID: orphan.id,
                safetyLevel: .safeNow,
                impactNote: "An toàn 100%: Không làm đóng cửa sổ Google Chrome bạn đang sử dụng.",
                actionLabel: "Dọn ngay"
            ))
        }

        // Surface any user app saturating CPU (e.g. ChatGPT / Codex / node / Loom) so user gets a direct Close + Info action
        if let hotUserApp = processGroups.first(where: {
            !$0.isOrphanAutomation
            && $0.guidance.safetyLevel == .cautionSaveFirst
            && ($0.totalCPUPercent >= 55.0 || $0.totalRSSBytes >= 2_500_000_000)
            && $0.id != "app:Google Chrome"
        }) {
            let isHotCPU = hotUserApp.totalCPUPercent >= 55.0
            score -= isHotCPU ? 14 : 8
            findings.append(DiagnosticFinding(
                id: "hot-user-app-\(hotUserApp.id)",
                severity: isHotCPU ? .warning : .warning,
                title: "\(hotUserApp.displayName) đang ngốn tải (\(Int(hotUserApp.totalCPUPercent))% CPU • \(Formatters.bytes(hotUserApp.totalRSSBytes)) RAM)",
                detail: hotUserApp.guidance.currentActivityHint,
                recommendedAction: hotUserApp.actionKind == .none ? .terminateUserProcess : hotUserApp.actionKind,
                targetID: hotUserApp.id,
                safetyLevel: hotUserApp.guidance.safetyLevel,
                impactNote: hotUserApp.guidance.impactIfClosed,
                actionLabel: "Đóng"
            ))
        }

        let compGB = snapshot.memory.compressedGB
        let swapGB = snapshot.memory.swapUsedGB
        if compGB >= 5.5 || swapGB >= 2.0 {
            score -= 25
            findings.append(DiagnosticFinding(
                id: "memory-compressor",
                severity: .critical,
                title: String(format: "RAM bị nén nặng (Nén %.1f GB • Swap %.1f GB)", compGB, swapGB),
                detail: "macOS đang thiếu RAM trống nên phải nén và đẩy ra SSD, dễ gây khựng khi thao tác.",
                recommendedAction: .openCleanerTab,
                targetID: "ram",
                safetyLevel: .safeNow,
                impactNote: "Mở mục Giải phóng RAM để đóng bớt tab trùng hoặc app rảnh đang ngốn RAM.",
                actionLabel: "Giải phóng RAM"
            ))
        } else if compGB >= 4.0 || swapGB >= 0.8 {
            score -= 12
            findings.append(DiagnosticFinding(
                id: "memory-compressor",
                severity: .warning,
                title: String(format: "RAM đang hơi căng (Nén %.1f GB)", compGB),
                detail: "Nên đóng bớt tab trình duyệt trùng hoặc app nặng đang chạy nền không dùng tới.",
                recommendedAction: .openCleanerTab,
                targetID: "ram",
                safetyLevel: .safeNow,
                impactNote: "Không dùng lệnh ép hệ thống — chỉ đóng app/tab bạn chọn để giải phóng RAM thật.",
                actionLabel: "Xem mục RAM"
            ))
        }

        if let chrome = processGroups.first(where: { $0.id == "app:Google Chrome" }), chrome.totalRSSBytes >= 4_000_000_000 {
            score -= 10
            findings.append(DiagnosticFinding(
                id: "chrome-heavy",
                severity: .warning,
                title: "Google Chrome đang dùng \(Formatters.bytes(chrome.totalRSSBytes)) (\(chrome.processCount) tiến trình)",
                detail: "Rà các tab mở lặp hoặc tab cũ không dùng để giữ lại các tab đang làm việc.",
                recommendedAction: .inspectBrowserTabs,
                targetID: chrome.id,
                safetyLevel: .cautionSaveFirst,
                impactNote: "Soi từng tab giúp bạn tắt chọn lọc mà không làm mất bài viết đang soạn.",
                actionLabel: "Soi tab"
            ))
        }

        let freeGB = snapshot.disk.availableGB
        if freeGB < 20.0 {
            score -= 20
            findings.append(DiagnosticFinding(
                id: "disk-low",
                severity: .critical,
                title: String(format: "Ổ cứng SSD chỉ còn %.1f GB trống", freeGB),
                detail: "APFS cần tối thiểu 25-30 GB trống để ghi swap và chạy ứng dụng mượt mà.",
                recommendedAction: .openCleanerTab,
                targetID: "ssd",
                safetyLevel: .safeNow,
                impactNote: "Vào tab Dọn dẹp để xoá cache an toàn và kiểm tra các file DB/Runtime nặng.",
                actionLabel: "Dọn SSD"
            ))
        } else if freeGB < 32.0 {
            score -= 8
            findings.append(DiagnosticFinding(
                id: "disk-low",
                severity: .warning,
                title: String(format: "Ổ cứng SSD còn %.1f GB trống (nên giữ >35 GB)", freeGB),
                detail: "Có thể xoá các cache trình duyệt/npm/pip an toàn để nới thêm dung lượng.",
                recommendedAction: .openCleanerTab,
                targetID: "ssd",
                safetyLevel: .safeNow,
                impactNote: "Xoá Cache chỉ dọn file đệm tạm trên SSD, không đụng dữ liệu cá nhân.",
                actionLabel: "Dọn Cache"
            ))
        }

        if snapshot.cpu.totalBusyPercent >= 75.0 || snapshot.cpu.load1m >= Double(snapshot.cpu.coreCount) * 0.85 {
            score -= 15
            findings.append(DiagnosticFinding(
                id: "cpu-high",
                severity: .warning,
                title: String(format: "CPU đang tải cao (%.0f%%, Load %.2f)", snapshot.cpu.totalBusyPercent, snapshot.cpu.load1m),
                detail: "Xem các dòng đầu ở mục Tiến trình bên dưới, rê chuột vào biểu tượng (i) để biết tác động trước khi Đóng.",
                recommendedAction: .none,
                safetyLevel: .cautionSaveFirst,
                impactNote: "Chỉ đóng các ứng dụng người dùng bạn không cần chạy ngay lúc này."
            ))
        }

        let clamped = max(0, min(100, score))
        let maxSeverity = findings.map(\.severity).max() ?? .ok
        let label: String
        switch maxSeverity {
        case .ok: label = "Máy đang mượt"
        case .warning: label = "Hơi nặng, cần chú ý"
        case .critical: label = "Đang quá tải, dễ khựng"
        }

        return HealthReport(
            score: clamped,
            statusLabel: label,
            severity: maxSeverity,
            findings: findings.sorted { $0.severity > $1.severity }
        )
    }
}
