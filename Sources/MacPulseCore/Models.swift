import Foundation

public enum Formatters {
    public static func bytes(_ count: UInt64) -> String {
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0
        let val = Double(count)
        if val >= gb { return String(format: "%.2f GB", val / gb) }
        if val >= mb { return String(format: "%.1f MB", val / mb) }
        if val >= kb { return String(format: "%.0f KB", val / kb) }
        return "\(count) B"
    }

    public static func bytesSigned(_ count: Int64) -> String {
        count < 0 ? "-\(bytes(UInt64(-count)))" : bytes(UInt64(count))
    }
}

public struct CPUMetrics: Sendable, Equatable {
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    public let coreCount: Int
    public let load1m: Double
    public let load5m: Double
    public let load15m: Double

    public var totalBusyPercent: Double { max(0, min(100, userPercent + systemPercent)) }

    public init(userPercent: Double, systemPercent: Double, idlePercent: Double, coreCount: Int, load1m: Double, load5m: Double, load15m: Double) {
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.coreCount = coreCount
        self.load1m = load1m
        self.load5m = load5m
        self.load15m = load15m
    }
}

public struct MemoryMetrics: Sendable, Equatable {
    public let totalBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let freeBytes: UInt64
    public let purgeableBytes: UInt64
    public let swapTotalBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapins: UInt64
    public let swapouts: UInt64

    public var compressedGB: Double { Double(compressedBytes) / 1_073_741_824.0 }
    public var freeGB: Double { Double(freeBytes) / 1_073_741_824.0 }
    public var swapUsedGB: Double { Double(swapUsedBytes) / 1_073_741_824.0 }
    public var usedBytes: UInt64 { activeBytes + wiredBytes + compressedBytes }
    public var availableBytes: UInt64 { totalBytes >= usedBytes ? totalBytes - usedBytes : freeBytes }
    public var availableGB: Double { Double(availableBytes) / 1_073_741_824.0 }
    public var totalGB: Double { Double(totalBytes) / 1_073_741_824.0 }
    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, Double(usedBytes) / Double(totalBytes) * 100.0)
    }
    public var isCompressorHeavy: Bool { compressedGB >= 4.5 }

    public init(totalBytes: UInt64, activeBytes: UInt64, inactiveBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, freeBytes: UInt64, purgeableBytes: UInt64, swapTotalBytes: UInt64, swapUsedBytes: UInt64, swapins: UInt64, swapouts: UInt64) {
        self.totalBytes = totalBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.freeBytes = freeBytes
        self.purgeableBytes = purgeableBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapins = swapins
        self.swapouts = swapouts
    }
}

public struct DiskMetrics: Sendable, Equatable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let usedBytes: UInt64

    public var totalGB: Double { Double(totalBytes) / 1_073_741_824.0 }
    public var availableGB: Double { Double(availableBytes) / 1_073_741_824.0 }
    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }

    public init(totalBytes: UInt64, availableBytes: UInt64, usedBytes: UInt64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.usedBytes = usedBytes
    }
}

public struct SystemSnapshot: Sendable, Equatable {
    public let timestamp: Date
    public let cpu: CPUMetrics
    public let memory: MemoryMetrics
    public let disk: DiskMetrics

    public init(timestamp: Date = Date(), cpu: CPUMetrics, memory: MemoryMetrics, disk: DiskMetrics) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
    }
}

public struct RawProcessInfo: Sendable, Equatable, Identifiable {
    public let id: Int32
    public var pid: Int32 { id }
    public let ppid: Int32
    public let cpuPercent: Double
    public let rssBytes: UInt64
    public let elapsed: String
    public let comm: String
    public let args: String

    public init(pid: Int32, ppid: Int32, cpuPercent: Double, rssBytes: UInt64, elapsed: String, comm: String, args: String) {
        self.id = pid
        self.ppid = ppid
        self.cpuPercent = cpuPercent
        self.rssBytes = rssBytes
        self.elapsed = elapsed
        self.comm = comm
        self.args = args
    }
}

public enum ProcessActionKind: String, Sendable, Equatable {
    case none
    case killOrphanPuppeteer
    case quitAppGracefully
    case terminateUserProcess
    case inspectBrowserTabs
    case openCleanerTab
}

public enum TerminationSafetyLevel: String, Sendable, Equatable {
    case safeNow          // Green: 0 work loss (orphan puppeteer, dup tabs, caches)
    case cautionSaveFirst // Yellow: User apps (ChatGPT, Local, Chrome, Slack, etc.)
    case remoteKeepAlive  // Orange: Remote tools (closing drops remote session)
    case systemProtected  // Red: macOS core daemons / MacPulse itself

    public var badgeLabel: String {
        switch self {
        case .safeNow: return "An toàn"
        case .cautionSaveFirst: return "Lưu trước"
        case .remoteKeepAlive: return "Đang remote"
        case .systemProtected: return "Hệ thống"
        }
    }
}

public struct ProcessGuidance: Sendable, Equatable {
    public let safetyLevel: TerminationSafetyLevel
    public let whatIsIt: String
    public let currentActivityHint: String
    public let impactIfClosed: String
    public let recommendedHowTo: String

    public init(
        safetyLevel: TerminationSafetyLevel,
        whatIsIt: String,
        currentActivityHint: String = "",
        impactIfClosed: String,
        recommendedHowTo: String
    ) {
        self.safetyLevel = safetyLevel
        self.whatIsIt = whatIsIt
        self.currentActivityHint = currentActivityHint
        self.impactIfClosed = impactIfClosed
        self.recommendedHowTo = recommendedHowTo
    }

    public static let defaultGeneral = ProcessGuidance(
        safetyLevel: .cautionSaveFirst,
        whatIsIt: "Tiến trình ứng dụng hoặc dịch vụ nền.",
        currentActivityHint: "Đang chiếm tài nguyên CPU hoặc RAM trên máy.",
        impactIfClosed: "Tắt trực tiếp có thể làm dừng tác vụ đang chạy dở của tiến trình này.",
        recommendedHowTo: "Kiểm tra xem bạn có đang dùng không rồi mới bấm Đóng."
    )
}

public struct ProcessGroupSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let processCount: Int
    public let totalCPUPercent: Double
    public let totalRSSBytes: UInt64
    public let pids: [Int32]
    public let bundleIdentifier: String?
    public let isOrphanAutomation: Bool
    public let actionKind: ProcessActionKind
    public let guidance: ProcessGuidance
    public let canForceTerminate: Bool

    public init(
        id: String,
        displayName: String,
        processCount: Int,
        totalCPUPercent: Double,
        totalRSSBytes: UInt64,
        pids: [Int32],
        bundleIdentifier: String? = nil,
        isOrphanAutomation: Bool = false,
        actionKind: ProcessActionKind = .none,
        guidance: ProcessGuidance = .defaultGeneral,
        canForceTerminate: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.processCount = processCount
        self.totalCPUPercent = totalCPUPercent
        self.totalRSSBytes = totalRSSBytes
        self.pids = pids
        self.bundleIdentifier = bundleIdentifier
        self.isOrphanAutomation = isOrphanAutomation
        self.actionKind = actionKind
        self.guidance = guidance
        self.canForceTerminate = canForceTerminate
    }
}

public enum Severity: String, Sendable, Equatable, Comparable {
    case ok, warning, critical
    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        let order: [Severity: Int] = [.ok: 0, .warning: 1, .critical: 2]
        return (order[lhs] ?? 0) < (order[rhs] ?? 0)
    }
}

public struct DiagnosticFinding: Sendable, Equatable, Identifiable {
    public let id: String
    public let severity: Severity
    public let title: String
    public let detail: String
    public let recommendedAction: ProcessActionKind
    public let targetID: String?
    public let safetyLevel: TerminationSafetyLevel
    public let impactNote: String
    public let actionLabel: String?

    public init(
        id: String,
        severity: Severity,
        title: String,
        detail: String,
        recommendedAction: ProcessActionKind = .none,
        targetID: String? = nil,
        safetyLevel: TerminationSafetyLevel = .cautionSaveFirst,
        impactNote: String = "",
        actionLabel: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.recommendedAction = recommendedAction
        self.targetID = targetID
        self.safetyLevel = safetyLevel
        self.impactNote = impactNote
        self.actionLabel = actionLabel
    }
}

public struct HealthReport: Sendable, Equatable {
    public let score: Int
    public let statusLabel: String
    public let severity: Severity
    public let findings: [DiagnosticFinding]

    public init(score: Int, statusLabel: String, severity: Severity, findings: [DiagnosticFinding]) {
        self.score = score
        self.statusLabel = statusLabel
        self.severity = severity
        self.findings = findings
    }
}

public struct BenchmarkResult: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let cpuSingleOpsPerSec: Double
    public let cpuMultiOpsPerSec: Double
    public let memoryBandwidthGBs: Double
    public let diskWriteMBs: Double
    public let diskReadMBs: Double
    public let localWPLatencyMs: Double?
    public let localWPStatusCode: Int?
    public let totalDurationSeconds: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), cpuSingleOpsPerSec: Double, cpuMultiOpsPerSec: Double, memoryBandwidthGBs: Double, diskWriteMBs: Double, diskReadMBs: Double, localWPLatencyMs: Double? = nil, localWPStatusCode: Int? = nil, totalDurationSeconds: Double) {
        self.id = id
        self.timestamp = timestamp
        self.cpuSingleOpsPerSec = cpuSingleOpsPerSec
        self.cpuMultiOpsPerSec = cpuMultiOpsPerSec
        self.memoryBandwidthGBs = memoryBandwidthGBs
        self.diskWriteMBs = diskWriteMBs
        self.diskReadMBs = diskReadMBs
        self.localWPLatencyMs = localWPLatencyMs
        self.localWPStatusCode = localWPStatusCode
        self.totalDurationSeconds = totalDurationSeconds
    }
}

public enum CleanupCategory: String, Sendable, Equatable {
    case cache
    case logsAndTrash
    case storageHeavyData

    public var title: String {
        switch self {
        case .cache: return "Cache (Bộ nhớ đệm tạm trên SSD)"
        case .logsAndTrash: return "Log phình to & Thùng rác"
        case .storageHeavyData: return "Dữ liệu & Runtime nặng trên ổ cứng"
        }
    }
}

public enum CleanupTier: String, Sendable, Equatable {
    case safeAutoClean
    case inspectOnly
}

public enum CleanupMethod: String, Sendable, Equatable {
    case clearDirectoryContents
    case truncateLogFile
    case emptyTrash
    case inspectInFinderOnly
}

public struct CleanupCandidate: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let path: String
    public let sizeBytes: UInt64
    public let tier: CleanupTier
    public let method: CleanupMethod
    public let defaultSelected: Bool
    public let category: CleanupCategory

    public init(
        id: String,
        title: String,
        subtitle: String,
        path: String,
        sizeBytes: UInt64,
        tier: CleanupTier,
        method: CleanupMethod,
        defaultSelected: Bool,
        category: CleanupCategory = .cache
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.sizeBytes = sizeBytes
        self.tier = tier
        self.method = method
        self.defaultSelected = defaultSelected
        self.category = category
    }
}

public struct CleanupOutcome: Sendable, Equatable {
    public let freedBytes: UInt64
    public let processedCount: Int
    public let errors: [String]

    public init(freedBytes: UInt64, processedCount: Int, errors: [String]) {
        self.freedBytes = freedBytes
        self.processedCount = processedCount
        self.errors = errors
    }
}

public struct BrowserTabItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let browser: String
    public let windowIndex: Int
    public let tabIndex: Int
    public let title: String
    public let url: String

    public init(browser: String, windowIndex: Int, tabIndex: Int, title: String, url: String) {
        self.id = "\(browser)-\(windowIndex)-\(tabIndex)-\(url)"
        self.browser = browser
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.title = title
        self.url = url
    }
}

public struct DuplicateTabGroup: Sendable, Equatable, Identifiable {
    public let id: String
    public let normalizedURL: String
    public let tabs: [BrowserTabItem]

    public init(normalizedURL: String, tabs: [BrowserTabItem]) {
        self.id = normalizedURL
        self.normalizedURL = normalizedURL
        self.tabs = tabs
    }
}
