import Foundation
import Darwin

public enum ProcessScanner {
    private struct CPUSample {
        let cpuNs: UInt64
        let timestampNs: UInt64
    }

    private static let sampleLock = NSLock()
    private static var previousCPUSamples: [Int32: CPUSample] = [:]
    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func machTimeToNs(_ raw: UInt64) -> UInt64 {
        let denom = UInt64(max(1, timebaseInfo.denom))
        return (raw / denom) * UInt64(timebaseInfo.numer) + ((raw % denom) * UInt64(timebaseInfo.numer)) / denom
    }

    public static func scanLiveProcesses() throws -> [RawProcessInfo] {
        sampleLock.lock()
        let needsWarmup = previousCPUSamples.isEmpty
        sampleLock.unlock()

        if needsWarmup {
            _ = captureNativeSnapshot()
            Thread.sleep(forTimeInterval: 0.15)
        }
        return captureNativeSnapshot()
    }

    private static func captureNativeSnapshot() -> [RawProcessInfo] {
        let bufferBytes = proc_listallpids(nil, 0)
        guard bufferBytes > 0 else { return [] }
        let estimatedCount = Int(bufferBytes) / MemoryLayout<pid_t>.stride + 64
        var pids = [pid_t](repeating: 0, count: estimatedCount)
        let actualBytes = pids.withUnsafeMutableBytes { buf in
            proc_listallpids(buf.baseAddress, Int32(buf.count))
        }
        guard actualBytes > 0 else { return [] }
        let pidCount = Int(actualBytes) / MemoryLayout<pid_t>.stride
        let nowNs = DispatchTime.now().uptimeNanoseconds
        let selfUID = getuid()

        var nextSamples: [Int32: CPUSample] = [:]
        nextSamples.reserveCapacity(pidCount)
        var results: [RawProcessInfo] = []
        results.reserveCapacity(pidCount)

        sampleLock.lock()
        let prevSamples = previousCPUSamples
        sampleLock.unlock()

        for i in 0..<pidCount {
            let pid = pids[i]
            if pid <= 0 { continue }

            var taskInfo = proc_taskinfo()
            let taskSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.stride))
            guard taskSize == Int32(MemoryLayout<proc_taskinfo>.stride) else { continue }

            var bsdInfo = proc_bsdinfo()
            let bsdSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.stride))
            let ppid: Int32 = bsdSize == Int32(MemoryLayout<proc_bsdinfo>.stride) ? Int32(bsdInfo.pbi_ppid) : 0
            let uid: UInt32 = bsdSize == Int32(MemoryLayout<proc_bsdinfo>.stride) ? bsdInfo.pbi_uid : 0

            let totalCPUNs = machTimeToNs(taskInfo.pti_total_user &+ taskInfo.pti_total_system)
            nextSamples[pid] = CPUSample(cpuNs: totalCPUNs, timestampNs: nowNs)

            var cpuPercent: Double = 0
            if let prev = prevSamples[pid], nowNs > prev.timestampNs, totalCPUNs >= prev.cpuNs {
                let dCPU = Double(totalCPUNs - prev.cpuNs)
                let dWall = Double(nowNs - prev.timestampNs)
                cpuPercent = min(1600.0, (dCPU / dWall) * 100.0)
            }

            let rssBytes = taskInfo.pti_resident_size
            let path = procPath(for: pid)
            let procNameStr = procName(for: pid)
            let args: String
            if uid == selfUID {
                args = readProcArgs(for: pid) ?? (path.isEmpty ? procNameStr : path)
            } else {
                args = path.isEmpty ? procNameStr : path
            }

            let comm = procNameStr.isEmpty ? extractBinaryName(from: args) : procNameStr
            results.append(RawProcessInfo(
                pid: pid,
                ppid: ppid,
                cpuPercent: cpuPercent,
                rssBytes: rssBytes,
                elapsed: "",
                comm: comm,
                args: args
            ))
        }

        sampleLock.lock()
        previousCPUSamples = nextSamples
        sampleLock.unlock()

        return results
    }

    private static func procName(for pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let len = proc_name(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return "" }
        return String(cString: buf)
    }

    private static func procPath(for pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return "" }
        return String(cString: buf)
    }

    private static func readProcArgs(for pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var data = Data(count: size)
        let rc = data.withUnsafeMutableBytes { ptr in
            sysctl(&mib, UInt32(mib.count), ptr.baseAddress, &size, nil, 0)
        }
        guard rc == 0, size > MemoryLayout<Int32>.size else { return nil }

        return data.withUnsafeBytes { rawBuf -> String? in
            let bytes = rawBuf.bindMemory(to: UInt8.self)
            guard bytes.count > MemoryLayout<Int32>.size else { return nil }
            var argc: Int32 = 0
            memcpy(&argc, bytes.baseAddress!, MemoryLayout<Int32>.size)

            var idx = MemoryLayout<Int32>.size
            // Skip exec_path C-string
            while idx < size && bytes[idx] != 0 { idx += 1 }
            // Skip trailing NUL padding after exec_path
            while idx < size && bytes[idx] == 0 { idx += 1 }

            var parts: [String] = []
            let limit = max(1, min(Int(argc), 24))
            while idx < size && parts.count < limit {
                let start = idx
                while idx < size && bytes[idx] != 0 { idx += 1 }
                if idx > start {
                    if let s = String(bytes: bytes[start..<idx], encoding: .utf8) {
                        parts.append(s)
                    }
                }
                idx += 1
            }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    public static func parsePSOutput(_ raw: String, hasHeader: Bool = true) -> [RawProcessInfo] {
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        if hasHeader, let first = lines.first, first.contains("PID") && first.contains("PPID") {
            lines.removeFirst()
        }

        var items: [RawProcessInfo] = []
        items.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            var fields: [Substring] = []
            var idx = trimmed.startIndex
            while fields.count < 5 && idx < trimmed.endIndex {
                while idx < trimmed.endIndex && trimmed[idx].isWhitespace {
                    idx = trimmed.index(after: idx)
                }
                let start = idx
                while idx < trimmed.endIndex && !trimmed[idx].isWhitespace {
                    idx = trimmed.index(after: idx)
                }
                if start < idx {
                    fields.append(trimmed[start..<idx])
                }
            }
            guard fields.count == 5,
                  let pid = Int32(fields[0]),
                  let ppid = Int32(fields[1]),
                  let cpu = Double(fields[2]),
                  let rssKB = UInt64(fields[3]) else {
                continue
            }
            while idx < trimmed.endIndex && trimmed[idx].isWhitespace {
                idx = trimmed.index(after: idx)
            }
            let args = String(trimmed[idx...])
            let comm = extractBinaryName(from: args)
            items.append(RawProcessInfo(
                pid: pid,
                ppid: ppid,
                cpuPercent: cpu,
                rssBytes: rssKB * 1024,
                elapsed: String(fields[4]),
                comm: comm,
                args: args
            ))
        }
        return items
    }

    public static func aggregate(_ processes: [RawProcessInfo]) -> [ProcessGroupSummary] {
        var orphanPIDs = Set<Int32>()
        for p in processes where isOrphanPuppeteerCommand(p.args) {
            orphanPIDs.insert(p.pid)
        }
        var changed = true
        while changed {
            changed = false
            for p in processes where !orphanPIDs.contains(p.pid) && orphanPIDs.contains(p.ppid) {
                orphanPIDs.insert(p.pid)
                changed = true
            }
        }

        struct Bucket {
            var displayName: String
            var pids: [Int32] = []
            var cpu: Double = 0
            var rss: UInt64 = 0
            var bundleID: String?
            var isOrphan: Bool = false
            var action: ProcessActionKind = .none
            var sampleArgs: String = ""
        }

        var buckets: [String: Bucket] = [:]

        for p in processes {
            if orphanPIDs.contains(p.pid) {
                let key = "orphan:puppeteer-chrome"
                var b = buckets[key] ?? Bucket(
                    displayName: "Chrome ngầm / Automation (Playwright/Puppeteer)",
                    bundleID: nil,
                    isOrphan: true,
                    action: .killOrphanPuppeteer,
                    sampleArgs: p.args
                )
                b.pids.append(p.pid)
                b.cpu += p.cpuPercent
                b.rss += p.rssBytes
                buckets[key] = b
                continue
            }

            let appInfo = classifyApp(from: p)
            var b = buckets[appInfo.key] ?? Bucket(
                displayName: appInfo.name,
                bundleID: appInfo.bundleID,
                isOrphan: false,
                action: appInfo.action,
                sampleArgs: p.args
            )
            if b.bundleID == nil, let bid = appInfo.bundleID {
                b.bundleID = bid
            }
            if b.action == .none && appInfo.action != .none {
                b.action = appInfo.action
            }
            b.pids.append(p.pid)
            b.cpu += p.cpuPercent
            b.rss += p.rssBytes
            buckets[appInfo.key] = b
        }

        return buckets.map { key, b in
            let guidance = buildGuidance(
                key: key,
                displayName: b.displayName,
                bundleID: b.bundleID,
                isOrphan: b.isOrphan,
                cpuPercent: b.cpu,
                rssBytes: b.rss,
                processCount: b.pids.count,
                sampleArgs: b.sampleArgs
            )
            let canForce = guidance.safetyLevel == .safeNow || guidance.safetyLevel == .cautionSaveFirst
            return ProcessGroupSummary(
                id: key,
                displayName: b.displayName,
                processCount: b.pids.count,
                totalCPUPercent: b.cpu,
                totalRSSBytes: b.rss,
                pids: b.pids,
                bundleIdentifier: b.bundleID,
                isOrphanAutomation: b.isOrphan,
                actionKind: b.action,
                guidance: guidance,
                canForceTerminate: canForce
            )
        }.sorted { lhs, rhs in
            func score(_ g: ProcessGroupSummary) -> Double {
                let isIdleTinySystem = (g.guidance.safetyLevel == .systemProtected && g.totalCPUPercent < 3.0 && g.totalRSSBytes < 120_000_000)
                let penalty: Double = isIdleTinySystem ? -1_000_000_000.0 : 0.0
                let orphanBonus: Double = g.isOrphanAutomation ? 500_000_000.0 : 0.0
                let userBonus: Double = (g.guidance.safetyLevel == .cautionSaveFirst) ? 200_000_000.0 : 0.0
                return g.totalCPUPercent * 32_000_000.0 + Double(g.totalRSSBytes) + orphanBonus + userBonus + penalty
            }
            return score(lhs) > score(rhs)
        }
    }

    public static func isOrphanPuppeteerCommand(_ args: String) -> Bool {
        let lower = args.lowercased()
        if lower.contains(".mac-remote-hub/chrome-profile")
            || lower.contains("remoting_me2me_host")
            || lower.contains("chromeremotedesktop") {
            return false
        }
        let isPuppeteer = (lower.contains("--enable-automation") || lower.contains("puppeteer_dev_chrome_profile"))
            && (lower.contains("puppeteer_") || lower.contains("chrome-devtools-mcp"))
        if isPuppeteer {
            return true
        }
        if lower.contains("playwright_chromiumdev_profile") {
            return true
        }
        let isChromeBinary = lower.contains("/applications/google chrome.app/") || lower.contains("google chrome.app/contents/")
        let isHeadlessFlag = lower.contains("--headless")
        let isAutomationFlag = lower.contains("--no-startup-window")
            || lower.contains("--remote-debugging-pipe")
            || lower.contains("--remote-debugging-port")
            || lower.contains("--enable-automation")
            || lower.contains("playwright")
            || lower.contains("puppeteer")
            || lower.contains("chrome-devtools-mcp")
        return isChromeBinary && isHeadlessFlag && isAutomationFlag
    }

    public static func isAnyGoogleChromeProcess(_ proc: RawProcessInfo) -> Bool {
        let lower = proc.args.lowercased()
        if lower.contains(".mac-remote-hub/chrome-profile")
            || lower.contains("remoting_me2me_host")
            || lower.contains("chromeremotedesktop") {
            return false
        }
        return lower.contains("/applications/google chrome.app/")
            || lower.contains("google chrome.app/contents/")
            || proc.comm.lowercased().hasPrefix("google chrome")
    }

    private static func extractBinaryName(from args: String) -> String {
        let beforeFlags = args.components(separatedBy: " --").first ?? args
        return URL(fileURLWithPath: beforeFlags.trimmingCharacters(in: .whitespaces)).lastPathComponent
    }

    private static let knownBundleMap: [String: String] = [
        "Google Chrome": "com.google.Chrome",
        "Microsoft Edge": "com.microsoft.edgemac",
        "Brave Browser": "com.brave.Browser",
        "Arc": "company.thebrowser.Browser",
        "Safari": "com.apple.Safari",
        "ChatGPT": "com.openai.chat",
        "Codex": "com.openai.codex",
        "Codex Computer Use": "com.openai.codex.computeruse",
        "Slack": "com.tinyspeck.slackmacgap",
        "Loom": "com.loom.desktop",
        "Local": "com.getflywheel.lightning.local",
        "AnyDesk": "com.philandro.anydesk",
        "9Remote": "com.9remote.app",
        "Visual Studio Code": "com.microsoft.VSCode",
        "Cursor": "com.todesktop.230313mzl4w4u92",
        "Warp": "dev.warp.Warp-Stable",
        "iTerm2": "com.googlecode.iterm2",
        "Terminal": "com.apple.Terminal",
        "Telegram": "ru.keepcoder.Telegram",
        "Zalo": "com.vng.zalo",
        "Figma": "com.figma.Desktop",
        "Xcode": "com.apple.dt.Xcode",
        "MacPulse": "com.ducdung.MacPulse"
    ]

    private static let remoteAppNames: Set<String> = [
        "9Remote", "AnyDesk", "ChromeRemoteDesktopHost", "Chrome Remote Desktop", "TeamViewer", "RustDesk"
    ]

    private static let protectedSystemAppNames: Set<String> = [
        "MacPulse", "Finder", "Dock", "WindowServer", "SystemUIServer", "ControlCenter", "NotificationCenter", "loginwindow", "CoreServicesUIAgent"
    ]

    private static func resolveBundleID(appName: String, appBundlePath: String) -> String? {
        if let known = knownBundleMap[appName] { return known }
        if FileManager.default.fileExists(atPath: appBundlePath),
           let bundle = Bundle(path: appBundlePath),
           let bid = bundle.bundleIdentifier {
            return bid
        }
        return nil
    }

    private static func classifyApp(from p: RawProcessInfo) -> (key: String, name: String, bundleID: String?, action: ProcessActionKind) {
        let args = p.args

        if args.contains("SkyComputerUseService") || args.contains("Codex Computer Use.app") {
            return ("app:ChatGPT-Codex-ComputerUse", "ChatGPT / Codex Computer Use", "com.openai.chat", .quitAppGracefully)
        }
        if args.contains("ChromeRemoteDesktopHost") || args.contains("remoting_me2me_host") {
            return ("remote:ChromeRemoteDesktop", "Chrome Remote Desktop", nil, .none)
        }
        if args.contains("9Remote") {
            return ("remote:9Remote", "9Remote (Remote Desktop)", "com.9remote.app", .none)
        }

        if let range = args.range(of: ".app/") {
            let appPathPrefix = String(args[..<range.upperBound].dropLast())
            // Climb out of nested helper .app inside main .app if any (e.g. Chrome.app/.../Chrome Helper.app)
            let topAppPath: String
            if let firstRange = appPathPrefix.range(of: ".app/") {
                topAppPath = String(appPathPrefix[..<firstRange.upperBound].dropLast())
            } else {
                topAppPath = appPathPrefix
            }
            let appName = URL(fileURLWithPath: topAppPath).deletingPathExtension().lastPathComponent
            let bundle = resolveBundleID(appName: appName, appBundlePath: topAppPath)

            if topAppPath.hasPrefix("/System/") || protectedSystemAppNames.contains(appName) {
                return ("sys:\(appName)", appName, bundle, .none)
            }
            if remoteAppNames.contains(appName) {
                return ("remote:\(appName)", appName, bundle, .none)
            }
            if appName == "Google Chrome" || appName == "Microsoft Edge" {
                return ("app:\(appName)", appName, bundle, .inspectBrowserTabs)
            }
            if bundle != nil {
                return ("app:\(appName)", appName, bundle, .quitAppGracefully)
            }
            return ("app:\(appName)", appName, nil, .terminateUserProcess)
        }

        if p.comm == "replayd" || args.contains("/usr/libexec/replayd") {
            return ("sys:replayd", "replayd (macOS ScreenCapture)", nil, .none)
        }
        if p.comm == "WindowServer" || args.contains("WindowServer") {
            return ("sys:WindowServer", "WindowServer (Đồ hoạ macOS)", nil, .none)
        }
        if p.comm == "kernel_task" || p.pid == 0 {
            return ("sys:kernel_task", "kernel_task (Nhân macOS)", nil, .none)
        }
        if p.comm == "sshd" || p.comm == "sftp-server" || p.comm == "tailscaled" || args.contains("sshd:") {
            return ("remote:\(p.comm)", "\(p.comm) (SSH/Remote)", nil, .none)
        }
        if args.hasPrefix("/System/") || args.hasPrefix("/usr/libexec/") || args.hasPrefix("/usr/sbin/") || args.hasPrefix("/sbin/") {
            let name = p.comm.isEmpty ? "System Daemon" : p.comm
            return ("sys:\(name)", "\(name) (macOS)", nil, .none)
        }

        let cleanName = p.comm.isEmpty ? "PID \(p.pid)" : p.comm
        let userClosableTools: Set<String> = ["node", "python3", "python", "claude", "codex", "opencode", "php", "mysqld", "nginx", "ffmpeg", "swift", "ruby", "java", "uvicorn"]
        if userClosableTools.contains(cleanName.lowercased()) || args.hasPrefix("/Users/") || args.hasPrefix("/opt/homebrew/") {
            return ("proc:\(cleanName)", cleanName, nil, .terminateUserProcess)
        }
        return ("proc:\(cleanName)", cleanName, nil, .none)
    }

    private static func buildGuidance(
        key: String,
        displayName: String,
        bundleID: String?,
        isOrphan: Bool,
        cpuPercent: Double,
        rssBytes: UInt64,
        processCount: Int,
        sampleArgs: String
    ) -> ProcessGuidance {
        let cpuText = String(format: "%.0f%% CPU", cpuPercent)
        let ramText = Formatters.bytes(rssBytes)
        let procText = processCount > 1 ? " (\(processCount) tiến trình)" : ""

        if isOrphan {
            return ProcessGuidance(
                safetyLevel: .safeNow,
                whatIsIt: "Trình duyệt Chrome chạy ẩn (--enable-automation) do tool/MCP hoặc script Puppeteer bật lên mà chưa tự thoát.",
                currentActivityHint: "Đang giữ ngầm \(ramText) RAM và \(cpuText)\(procText) mà không có cửa sổ hiển thị cho bạn.",
                impactIfClosed: "Không ảnh hưởng tới Google Chrome chính bạn đang mở (giữ nguyên toàn bộ tab, WordPress, mật khẩu).",
                recommendedHowTo: "Bấm \"Dọn ngay\" để giải phóng tức thì \(ramText) RAM."
            )
        }

        if key.hasPrefix("remote:") {
            return ProcessGuidance(
                safetyLevel: .remoteKeepAlive,
                whatIsIt: "Ứng dụng điều khiển máy tính từ xa (\(displayName)).",
                currentActivityHint: "Đang duy trì kết nối hình ảnh và bàn phím/chuột từ xa (\(cpuText), \(ramText)).",
                impactIfClosed: "Nếu tắt ngay bây giờ, phiên điều khiển từ xa hiện tại sẽ bị ngắt kết nối lập tức.",
                recommendedHowTo: "Giữ nguyên khi đang làm việc từ xa. Chỉ thoát trực tiếp khi bạn ngồi tại máy."
            )
        }

        if key.hasPrefix("sys:") || displayName == "MacPulse" {
            if key == "sys:replayd" {
                return ProcessGuidance(
                    safetyLevel: .systemProtected,
                    whatIsIt: "Dịch vụ chia sẻ/quay màn hình gốc của macOS (ScreenCapture daemon).",
                    currentActivityHint: cpuPercent >= 20
                        ? "Đang nhận yêu cầu chụp/đọc màn hình liên tục (\(cpuText)). Thường do app AI (ChatGPT/Codex), Loom hoặc automation kích hoạt."
                        : "Đang trực chờ chia sẻ màn hình ở mức nhẹ (\(cpuText), \(ramText)).",
                    impactIfClosed: "Đây là tiến trình lõi macOS — không nên tắt trực tiếp vì hệ thống sẽ tự bật lại ngay hoặc ngắt quay màn hình.",
                    recommendedHowTo: "Hãy đóng app đang gọi chụp màn hình (như ChatGPT, Codex Computer Use, Loom) thì replayd sẽ tự hạ tải."
                )
            }
            if displayName == "MacPulse" {
                return ProcessGuidance(
                    safetyLevel: .systemProtected,
                    whatIsIt: "Chính ứng dụng MacPulse đang chạy bộ gõ tiếng Việt & theo dõi hiệu năng.",
                    currentActivityHint: "Đang chạy bộ gõ EVKey và theo dõi máy (\(cpuText), \(ramText)).",
                    impactIfClosed: "Tắt sẽ dừng luôn bộ gõ tiếng Việt MacPulse và thanh đo menu bar.",
                    recommendedHowTo: "Nếu muốn thoát hẳn, dùng nút Thoát ở góc dưới cùng."
                )
            }
            return ProcessGuidance(
                safetyLevel: .systemProtected,
                whatIsIt: "Tiến trình hệ thống cốt lõi của macOS (\(displayName)).",
                currentActivityHint: "Đang xử lý giao diện, đồ hoạ hoặc dịch vụ nền của macOS (\(cpuText), \(ramText)\(procText)).",
                impactIfClosed: "Không thể tự đóng an toàn; ép tắt có thể làm văng phiên đăng nhập hoặc đen màn hình tạm thời.",
                recommendedHowTo: "Giữ nguyên. Để giảm tải cho nó, hãy đóng bớt các app hoặc tab trình duyệt nặng bên dưới."
            )
        }

        let lower = displayName.lowercased()
        if lower.contains("chatgpt") || lower.contains("codex") {
            let stateHint: String
            if cpuPercent >= 25.0 {
                stateHint = "Đang hoạt động mạnh (\(cpuText), \(ramText)\(procText)) — nhiều khả năng đang trả lời, chạy agent Codex hoặc quét màn hình."
            } else if rssBytes >= 700_000_000 {
                stateHint = "Đang ngâm bộ nhớ lớn (\(ramText) RAM, \(cpuText)\(procText)) do giao diện Electron/WebView hoặc nhiều hội thoại mở sẵn."
            } else {
                stateHint = "Đang chạy nền giữ phiên đăng nhập & cửa sổ chat (\(cpuText), \(ramText)\(procText))."
            }
            return ProcessGuidance(
                safetyLevel: .cautionSaveFirst,
                whatIsIt: "Ứng dụng ChatGPT / Codex Desktop trên macOS.",
                currentActivityHint: stateHint,
                impactIfClosed: "Đóng nhẹ (Cmd+Q) sẽ dừng ngay câu trả lời hoặc tác vụ agent đang chạy dở. Lịch sử đã gửi lên tài khoản vẫn còn khi mở lại; nội dung gõ nháp chưa gửi có thể mất.",
                recommendedHowTo: "Nếu không cần AI xử lý ngay lúc này, bấm \"Đóng\" để trả lại \(ramText) RAM và hạ CPU lập tức (nếu đơ thì chọn Ép tắt)."
            )
        }

        if displayName == "Google Chrome" || displayName == "Microsoft Edge" || displayName == "Brave Browser" || displayName == "Arc" || displayName == "Safari" {
            let tabCountHint = processCount > 8 ? " đang mở rất nhiều tab/extension (\(processCount) tiến trình con)." : " (\(processCount) tiến trình)."
            return ProcessGuidance(
                safetyLevel: .cautionSaveFirst,
                whatIsIt: "Trình duyệt web \(displayName).",
                currentActivityHint: "Đang chiếm \(ramText) RAM và \(cpuText)\(tabCountHint)",
                impactIfClosed: "Nếu đóng cả trình duyệt, bài viết WordPress hoặc form chưa bấm Lưu có thể bị mất; các tab bình thường có thể mở lại bằng Cmd+Shift+T.",
                recommendedHowTo: "Nên bấm \"Soi tab\" để tắt từng tab thừa/nặng trước, hoặc chọn \"Đóng cả app\" trong hộp xác nhận nếu đã lưu hết."
            )
        }

        if displayName == "Local" {
            return ProcessGuidance(
                safetyLevel: .cautionSaveFirst,
                whatIsIt: "Ứng dụng LocalWP chạy server PHP / MySQL / Nginx cho các web WordPress cục bộ.",
                currentActivityHint: "Đang chạy máy chủ web local (\(ramText) RAM, \(cpuText)\(procText)).",
                impactIfClosed: "Các trang WordPress trên *.local đang bật sẽ ngừng phản hồi cho tới khi bạn mở lại Local. Dữ liệu database không bị mất nếu đóng nhẹ.",
                recommendedHowTo: "Bấm \"Đóng\" khi bạn tạm ngưng code WordPress để giải phóng RAM (tránh Ép tắt để MySQL đóng sạch)."
            )
        }

        if lower.contains("node") || lower.contains("python") || lower.contains("claude") || lower.contains("opencode") || lower.contains("php") {
            let argSnippet = sampleArgs.split(separator: " ").prefix(2).joined(separator: " ")
            return ProcessGuidance(
                safetyLevel: .cautionSaveFirst,
                whatIsIt: "Tiến trình công cụ dòng lệnh / server dev (\(displayName)).",
                currentActivityHint: "Đang chạy nền với \(cpuText), \(ramText)\(procText). Lệnh: \(argSnippet.isEmpty ? displayName : argSnippet)",
                impactIfClosed: "Tắt sẽ ngắt tiến trình terminal/dev server hoặc CLI agent đang chạy.",
                recommendedHowTo: "Nếu đó là dev server cũ hoặc CLI bị kẹt quên tắt, có thể bấm \"Đóng\" để giải phóng \(ramText) RAM."
            )
        }

        return ProcessGuidance(
            safetyLevel: .cautionSaveFirst,
            whatIsIt: bundleID != nil ? "Ứng dụng người dùng macOS (\(displayName))." : "Tiến trình người dùng (\(displayName)).",
            currentActivityHint: cpuPercent >= 20
                ? "Đang xử lý tác vụ khá nặng (\(cpuText), \(ramText)\(procText))."
                : "Đang mở và giữ \(ramText) RAM (\(cpuText)\(procText)).",
            impactIfClosed: "Đóng nhẹ tương đương bấm Cmd+Q: app sẽ hỏi lưu file dở nếu hỗ trợ, dữ liệu chưa lưu có thể mất nếu không kịp lưu.",
            recommendedHowTo: "Lưu tài liệu đang làm trong \(displayName) (nếu có) rồi bấm \"Đóng\" khi muốn thu hồi \(ramText) RAM."
        )
    }
}
