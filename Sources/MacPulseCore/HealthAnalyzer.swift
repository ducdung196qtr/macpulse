import Foundation

public enum HealthAnalyzer {
    public static func analyze(
        snapshot: SystemSnapshot,
        processGroups: [ProcessGroupSummary],
        stuckChromeRendererCount: Int = 0,
        stuckChromeRendererCPU: Double = 0,
        chromeGPUCPU: Double = 0
    ) -> HealthReport {
        var score = 100
        var findings: [DiagnosticFinding] = []

        if snapshot.thermalLevel == .serious || snapshot.thermalLevel == .critical {
            let isCrit = snapshot.thermalLevel == .critical
            score -= isCrit ? 18 : 10
            findings.append(DiagnosticFinding(
                id: "thermal-pressure",
                severity: isCrit ? .critical : .warning,
                title: "Nhiệt độ máy ở mức \(snapshot.thermalLevel.label)",
                detail: "macOS đang kích hoạt giảm xung nhiệt (Thermal Throttling) để bảo vệ chip.",
                recommendedAction: .none,
                targetID: nil,
                safetyLevel: .cautionSaveFirst,
                impactNote: "Đóng bớt tiến trình ăn CPU cao hoặc dừng cụm Chrome headless bên dưới để hạ nhiệt nhanh."
            ))
        }

        if let replayd = processGroups.first(where: { $0.id == "sys:replayd" }), replayd.totalCPUPercent >= 25.0 {
            let isSevere = replayd.totalCPUPercent >= 60.0
            score -= isSevere ? 30 : 15
            let chromeCPU = processGroups.first(where: { $0.id == "app:Google Chrome" })?.totalCPUPercent ?? 0
            let chromeNote = chromeCPU >= 15.0
                ? " Đang kéo Google Chrome lên \(Int(chromeCPU))% CPU & gây bão XPC (_Xmach_notify_port_destroyed)."
                : " Lỗi vòng lặp XPC của ScreenCapture đang đốt CPU cho Chrome, ChatGPT & WindowServer."

            findings.append(DiagnosticFinding(
                id: "replayd-storm",
                severity: isSevere ? .critical : .warning,
                title: "replayd bị treo vòng lặp XPC (\(Int(replayd.totalCPUPercent))% CPU)",
                detail: "/usr/libexec/replayd đang kẹt vòng lặp ngốn CPU liên tục.\(chromeNote)",
                recommendedAction: .restartReplayd,
                targetID: "sys:replayd",
                safetyLevel: .safeNow,
                impactNote: "An toàn 100%: Restart sạch replayd để launchd khởi chạy lại ở 0% CPU — giải cứu tức thì Chrome & toàn máy mà KHÔNG đóng tab hay mất dữ liệu.",
                actionLabel: "Reset replayd ngay"
            ))
        }

        if let orphan = processGroups.first(where: { $0.isOrphanAutomation }) {
            let hasLiveGUIChrome = processGroups.contains { $0.id == "app:Google Chrome" && !$0.isOrphanAutomation }
            score -= 15
            let title = hasLiveGUIChrome
                ? "Chrome automation chạy ngầm (\(Formatters.bytes(orphan.totalRSSBytes)))"
                : "Chrome bị chặn mở bởi tiến trình ngầm (\(Formatters.bytes(orphan.totalRSSBytes)))"
            let detail = hasLiveGUIChrome
                ? "Cụm Chrome headless / agent-browser đang chạy ngầm (\(Int(orphan.totalCPUPercent))% CPU • \(orphan.processCount) tiến trình)."
                : "Phát hiện cụm Chrome headless ngầm (agent-browser/OpenMausBot/Playwright) đang giữ khoá profile Google Chrome."
            let actionLabel = hasLiveGUIChrome ? "Dừng & Reset" : "Gỡ kẹt & Mở Chrome"

            findings.append(DiagnosticFinding(
                id: "orphan-puppeteer",
                severity: orphan.totalCPUPercent >= 40 ? .critical : .warning,
                title: title,
                detail: detail,
                recommendedAction: .killOrphanPuppeteer,
                targetID: orphan.id,
                safetyLevel: .safeNow,
                impactNote: "An toàn 100%: Dừng cụm bot ngầm & gỡ khoá profile, không đụng Chrome thường đang mở.",
                actionLabel: actionLabel
            ))
        }

        if stuckChromeRendererCount > 0 && (stuckChromeRendererCPU >= 15.0 || (stuckChromeRendererCPU >= 8.0 && chromeGPUCPU >= 8.0)) {
            let gpuNote = chromeGPUCPU >= 8.0 ? " + GPU Chrome \(Int(chromeGPUCPU))% CPU" : ""
            score -= stuckChromeRendererCPU >= 50.0 ? 15 : 10
            findings.append(DiagnosticFinding(
                id: "stuck-chrome-renderers",
                severity: stuckChromeRendererCPU >= 60 ? .critical : .warning,
                title: "\(stuckChromeRendererCount) tab Chrome lặp JS/DOM (\(Int(stuckChromeRendererCPU))% CPU\(gpuNote))",
                detail: "Tab web hoặc vòng lặp JS/DOM đang ngốn CPU & GPU liên tục, dễ làm đơ và phình RAM Chrome.",
                recommendedAction: .killStuckChromeRenderers,
                targetID: "app:Google Chrome",
                safetyLevel: .safeNow,
                impactNote: "Chỉ dừng riêng tab bị treo (hiện trang Aw Snap để F5), giữ nguyên 100% tab khác & Extension.",
                actionLabel: "Gỡ kẹt tab"
            ))
        } else if chromeGPUCPU >= 18.0 {
            score -= 8
            findings.append(DiagnosticFinding(
                id: "chrome-gpu-loop",
                severity: .warning,
                title: "GPU Chrome đang quá tải (\(Int(chromeGPUCPU))% CPU)",
                detail: "Tiến trình GPU của Chrome đang dựng hình/compositor liên tục gây nóng máy và giật cuộn trang.",
                recommendedAction: .resetChromeGPU,
                targetID: "app:Google Chrome",
                safetyLevel: .safeNow,
                impactNote: "An toàn 100%: Reset riêng tiến trình GPU Chrome (tự phục hồi trong <0.5s), KHÔNG đóng tab hay mất form.",
                actionLabel: "Reset GPU Chrome"
            ))
        }

        // Surface up to 2 user apps saturating CPU or RAM so user gets direct Close + Info actions
        let hotUserApps = processGroups.filter {
            !$0.isOrphanAutomation
            && $0.guidance.safetyLevel == .cautionSaveFirst
            && ($0.totalCPUPercent >= 55.0 || $0.totalRSSBytes >= 2_500_000_000)
            && $0.id != "app:Google Chrome"
        }.prefix(2)

        for hotUserApp in hotUserApps {
            let isHotCPU = hotUserApp.totalCPUPercent >= 55.0
            score -= isHotCPU ? 12 : 7
            findings.append(DiagnosticFinding(
                id: "hot-user-app-\(hotUserApp.id)",
                severity: .warning,
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
