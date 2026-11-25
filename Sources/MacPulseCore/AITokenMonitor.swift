import Foundation
import Darwin
import SQLite3

public enum AIProviderType: String, Sendable, CaseIterable, Codable {
    case antigravity = "antigravity"
    case openaiCodex = "openai_codex"
    case commandcode = "commandcode"
    case claude = "claude"
}

public enum AIQuotaSourceState: String, Sendable, Equatable, Codable {
    case live
    case cached
    case offline

    public var badgeLabel: String {
        switch self {
        case .live: return "LIVE"
        case .cached: return "CACHED"
        case .offline: return "OFFLINE"
        }
    }
}

public struct AIWindowQuota: Sendable, Equatable, Codable {
    public let name: String               // e.g. "Phiên 5 Giờ", "Giới Hạn Tuần"
    public let windowSeconds: Int         // 18000 (5h) hoặc 604800 (7d)
    public let usedPercent: Double        // 0.0 ... 100.0
    public let remainingPercent: Double   // 100.0 - usedPercent
    public let resetAfterSeconds: Int?
    public let resetAt: Date?
    public let windowTokensUsed: Int?     // Tokens tiêu thụ trong window (nếu tính được)
    public let note: String?              // Model, trạng thái hoặc ghi chú

    public init(
        name: String,
        windowSeconds: Int,
        usedPercent: Double,
        resetAfterSeconds: Int? = nil,
        resetAt: Date? = nil,
        windowTokensUsed: Int? = nil,
        note: String? = nil
    ) {
        self.name = name
        self.windowSeconds = windowSeconds
        let clampedUsed = min(max(usedPercent, 0.0), 100.0)
        self.usedPercent = clampedUsed
        self.remainingPercent = 100.0 - clampedUsed
        self.resetAfterSeconds = resetAfterSeconds
        self.resetAt = resetAt
        self.windowTokensUsed = windowTokensUsed
        self.note = note
    }

    public var formattedRemainingPercent: String {
        String(format: "%.1f%%", remainingPercent)
    }

    public var formattedUsedPercent: String {
        String(format: "%.1f%%", usedPercent)
    }

    public func formattedResetCountdown(relativeTo now: Date = Date()) -> String {
        if let resetAt = resetAt {
            let diff = Int(resetAt.timeIntervalSince(now))
            if diff <= 0 {
                return "Sắp làm mới"
            }
            return Self.formatDuration(seconds: diff)
        }
        if let secs = resetAfterSeconds, secs > 0 {
            return Self.formatDuration(seconds: secs)
        }
        return "Tự động hồi"
    }

    public var formattedResetCountdown: String {
        formattedResetCountdown(relativeTo: Date())
    }

    public static func formatDuration(seconds: Int) -> String {
        if seconds >= 86400 {
            let days = seconds / 86400
            let hours = (seconds % 86400) / 3600
            return "\(days)d \(hours)h"
        } else if seconds >= 3600 {
            let hours = seconds / 3600
            let mins = (seconds % 3600) / 60
            return "\(hours)h \(String(format: "%02d", mins))m"
        } else if seconds >= 60 {
            let mins = seconds / 60
            return "\(mins) phút"
        } else {
            return "\(max(0, seconds))s"
        }
    }
}

public struct AIQuotaPool: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let label: String
    public let modelSummary: String
    public let quota: AIWindowQuota

    public init(id: String, label: String, modelSummary: String, quota: AIWindowQuota) {
        self.id = id
        self.label = label
        self.modelSummary = modelSummary
        self.quota = quota
    }
}

public struct AIProviderMetrics: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let providerType: AIProviderType
    public let iconName: String
    public let isDetected: Bool
    public let statusMessage: String
    public let activeModel: String?
    public let userAccount: String?
    public let planTier: String? // "Google AI Ultra", "ChatGPT Plus"

    // Quota windows (5h & Week) + multi-pool support
    public let fiveHourQuota: AIWindowQuota?
    public let weeklyQuota: AIWindowQuota?
    public let quotaPools: [AIQuotaPool]
    public let sourceState: AIQuotaSourceState

    // Credits / extra rate-limit metadata
    public let promptCreditsAvailable: Int?
    public let flowCreditsAvailable: Int?
    public let resetCreditsAvailable: Int?
    public let limitReached: Bool

    // Token metrics
    public let inputTokensToday: Int
    public let outputTokensToday: Int
    public let cacheTokensToday: Int
    public let totalTokensToday: Int
    public let tokensLast5Hours: Int
    public let tokensLast7Days: Int

    // Activity
    public let turnsOrPromptsToday: Int
    public let activeSessionsToday: Int
    public let estimatedCostTodayUSD: Double?
    public let remainingBalanceUSD: Double?
    public let lastSyncTime: Date

    public init(
        id: String,
        name: String,
        providerType: AIProviderType,
        iconName: String,
        isDetected: Bool,
        statusMessage: String,
        activeModel: String? = nil,
        userAccount: String? = nil,
        planTier: String? = nil,
        fiveHourQuota: AIWindowQuota? = nil,
        weeklyQuota: AIWindowQuota? = nil,
        quotaPools: [AIQuotaPool] = [],
        sourceState: AIQuotaSourceState = .live,
        promptCreditsAvailable: Int? = nil,
        flowCreditsAvailable: Int? = nil,
        resetCreditsAvailable: Int? = nil,
        limitReached: Bool = false,
        inputTokensToday: Int = 0,
        outputTokensToday: Int = 0,
        cacheTokensToday: Int = 0,
        totalTokensToday: Int = 0,
        tokensLast5Hours: Int = 0,
        tokensLast7Days: Int = 0,
        turnsOrPromptsToday: Int = 0,
        activeSessionsToday: Int = 0,
        estimatedCostTodayUSD: Double? = nil,
        remainingBalanceUSD: Double? = nil,
        lastSyncTime: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.iconName = iconName
        self.isDetected = isDetected
        self.statusMessage = statusMessage
        self.activeModel = activeModel
        self.userAccount = userAccount
        self.planTier = planTier
        self.fiveHourQuota = fiveHourQuota
        self.weeklyQuota = weeklyQuota
        self.quotaPools = quotaPools
        self.sourceState = sourceState
        self.promptCreditsAvailable = promptCreditsAvailable
        self.flowCreditsAvailable = flowCreditsAvailable
        self.resetCreditsAvailable = resetCreditsAvailable
        self.limitReached = limitReached
        self.inputTokensToday = inputTokensToday
        self.outputTokensToday = outputTokensToday
        self.cacheTokensToday = cacheTokensToday
        self.totalTokensToday = totalTokensToday
        self.tokensLast5Hours = tokensLast5Hours
        self.tokensLast7Days = tokensLast7Days
        self.turnsOrPromptsToday = turnsOrPromptsToday
        self.activeSessionsToday = activeSessionsToday
        self.estimatedCostTodayUSD = estimatedCostTodayUSD
        self.remainingBalanceUSD = remainingBalanceUSD
        self.lastSyncTime = lastSyncTime
    }

    public var formattedTokensToday: String {
        Self.formatTokenNumber(totalTokensToday)
    }

    public var formattedTokensLast5Hours: String {
        Self.formatTokenNumber(tokensLast5Hours)
    }

    public var formattedTokensLast7Days: String {
        Self.formatTokenNumber(tokensLast7Days)
    }

    public static func formatTokenNumber(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", Double(count) / 1_000_000_000.0)
        } else if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}

public struct AITokenSnapshot: Sendable, Equatable, Codable {
    public let providers: [AIProviderMetrics]
    public let grandTotalTokensToday: Int
    public let activeProvidersCount: Int
    public let timestamp: Date

    public init(providers: [AIProviderMetrics], grandTotalTokensToday: Int, activeProvidersCount: Int, timestamp: Date = Date()) {
        self.providers = providers
        self.grandTotalTokensToday = grandTotalTokensToday
        self.activeProvidersCount = activeProvidersCount
        self.timestamp = timestamp
    }

    public var formattedGrandTotal: String {
        AIProviderMetrics.formatTokenNumber(grandTotalTokensToday)
    }

    public var antigravity: AIProviderMetrics? {
        providers.first { $0.providerType == .antigravity }
    }

    public var chatGPT: AIProviderMetrics? {
        providers.first { $0.providerType == .openaiCodex }
    }
}

private struct CachedAIQuotaStore: Codable {
    var antigravity: CachedProviderQuota?
    var chatGPT: CachedProviderQuota?

    struct CachedProviderQuota: Codable {
        let savedAt: Date
        let planTier: String?
        let userAccount: String?
        let activeModel: String?
        let fiveHourQuota: AIWindowQuota?
        let weeklyQuota: AIWindowQuota?
        let quotaPools: [AIQuotaPool]
        let promptCreditsAvailable: Int?
        let flowCreditsAvailable: Int?
        let resetCreditsAvailable: Int?
        let limitReached: Bool
    }
}

public final class AITokenMonitor: @unchecked Sendable {
    public static let shared = AITokenMonitor()
    public let cacheFileURL: URL
    private let cacheLock = NSLock()

    public init(cacheFileURL: URL? = nil) {
        if let cacheFileURL {
            self.cacheFileURL = cacheFileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            self.cacheFileURL = appSupport
                .appendingPathComponent("MacPulse", isDirectory: true)
                .appendingPathComponent("ai-quota-cache.json")
        }
    }

    public static func currentDateString(date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: date)
    }

    private func loadCache() -> CachedAIQuotaStore {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode(CachedAIQuotaStore.self, from: data) else {
            return CachedAIQuotaStore()
        }
        return decoded
    }

    private func saveCache(_ mutate: (inout CachedAIQuotaStore) -> Void) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        var store: CachedAIQuotaStore
        if let data = try? Data(contentsOf: cacheFileURL),
           let decoded = try? JSONDecoder().decode(CachedAIQuotaStore.self, from: data) {
            store = decoded
        } else {
            store = CachedAIQuotaStore()
        }
        mutate(&store)
        let dir = cacheFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(store) {
            try? encoded.write(to: cacheFileURL, options: .atomic)
        }
    }

    public func scanAll(todayDateString: String? = nil) -> AITokenSnapshot {
        let today = todayDateString ?? Self.currentDateString()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Scan providers concurrently to halve wall-clock latency
        let group = DispatchGroup()
        let resultLock = NSLock()
        var p1: AIProviderMetrics?
        var p2: AIProviderMetrics?
        var p3: AIProviderMetrics?
        var p4: AIProviderMetrics?

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let m = self.scanAntigravity(home: home, today: today)
            resultLock.lock(); p1 = m; resultLock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let m = self.scanOpenAICodex(home: home, today: today)
            resultLock.lock(); p2 = m; resultLock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let m = self.scanCommandCode(home: home, today: today)
            resultLock.lock(); p3 = m; resultLock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let m = self.scanClaudeCode(home: home)
            resultLock.lock(); p4 = m; resultLock.unlock()
            group.leave()
        }

        group.wait()

        let providers = [p1, p2, p3, p4].compactMap { $0 }
        let grandTotal = providers.reduce(0) { $0 + $1.totalTokensToday }
        let activeCount = providers.filter { $0.isDetected }.count

        return AITokenSnapshot(
            providers: providers,
            grandTotalTokensToday: grandTotal,
            activeProvidersCount: activeCount,
            timestamp: Date()
        )
    }

    // MARK: - Google Antigravity Scanner
    public func scanAntigravity(home: String, today: String, referenceDate: Date = Date()) -> AIProviderMetrics {
        let agyDir = "\(home)/.gemini/antigravity"
        let fm = FileManager.default

        guard fm.fileExists(atPath: agyDir) else {
            return AIProviderMetrics(
                id: "antigravity",
                name: "Google Antigravity",
                providerType: .antigravity,
                iconName: "brain.head.profile",
                isDetected: false,
                statusMessage: "Chưa cài đặt (~/.gemini/antigravity)",
                sourceState: .offline
            )
        }

        var planTier: String? = nil
        var userAccount: String? = nil
        var activeModel: String? = nil
        var fiveHourQuota: AIWindowQuota? = nil
        var quotaPools: [AIQuotaPool] = []
        var promptCredits: Int? = nil
        var flowCredits: Int? = nil
        var sourceState: AIQuotaSourceState = .offline
        var lastSync = referenceDate

        // 1. Query Antigravity daemon language server on localhost for live quota
        if let liveStatus = queryAntigravityDaemon(agyDir: agyDir) {
            planTier = liveStatus.planTier
            userAccount = liveStatus.userAccount
            activeModel = liveStatus.activeModel
            fiveHourQuota = liveStatus.fiveHourQuota
            quotaPools = liveStatus.quotaPools
            promptCredits = liveStatus.promptCreditsAvailable
            flowCredits = liveStatus.flowCreditsAvailable
            sourceState = .live
            lastSync = referenceDate

            saveCache { store in
                store.antigravity = CachedAIQuotaStore.CachedProviderQuota(
                    savedAt: referenceDate,
                    planTier: planTier,
                    userAccount: userAccount,
                    activeModel: activeModel,
                    fiveHourQuota: fiveHourQuota,
                    weeklyQuota: nil,
                    quotaPools: quotaPools,
                    promptCreditsAvailable: promptCredits,
                    flowCreditsAvailable: flowCredits,
                    resetCreditsAvailable: nil,
                    limitReached: false
                )
            }
        } else if let cached = loadCache().antigravity {
            planTier = cached.planTier
            userAccount = cached.userAccount
            activeModel = cached.activeModel
            fiveHourQuota = cached.fiveHourQuota
            quotaPools = cached.quotaPools
            promptCredits = cached.promptCreditsAvailable
            flowCredits = cached.flowCreditsAvailable
            sourceState = .cached
            lastSync = cached.savedAt
        }

        // 2. Scan local SQLite & transcripts with accurate timezone-aware date boundaries
        let usage = Self.scanAntigravityTranscriptTokens(agyDir: agyDir, now: referenceDate)

        let estCost = (Double(usage.inputToday) * 0.075 / 1_000_000.0) + (Double(usage.outputToday) * 0.30 / 1_000_000.0)

        let status: String
        switch sourceState {
        case .live:
            status = userAccount != nil ? "Kết nối daemon • \(userAccount!)" : "Đang kết nối daemon nội bộ"
        case .cached:
            status = "Daemon tạm tắt • Hiển thị dữ liệu lưu gần nhất"
        case .offline:
            status = "Mở Antigravity để đồng bộ quota trực tiếp"
        }

        return AIProviderMetrics(
            id: "antigravity",
            name: "Google Antigravity",
            providerType: .antigravity,
            iconName: "brain.head.profile",
            isDetected: true,
            statusMessage: status,
            activeModel: activeModel,
            userAccount: userAccount ?? "Google AI Account",
            planTier: planTier ?? "Google AI",
            fiveHourQuota: fiveHourQuota,
            weeklyQuota: nil,
            quotaPools: quotaPools,
            sourceState: sourceState,
            promptCreditsAvailable: promptCredits,
            flowCreditsAvailable: flowCredits,
            inputTokensToday: usage.inputToday,
            outputTokensToday: usage.outputToday,
            cacheTokensToday: usage.cacheToday,
            totalTokensToday: usage.totalToday,
            tokensLast5Hours: usage.tokens5H,
            tokensLast7Days: usage.tokens7D,
            turnsOrPromptsToday: usage.turnsToday,
            activeSessionsToday: usage.sessionsToday,
            estimatedCostTodayUSD: estCost,
            lastSyncTime: lastSync
        )
    }

    public struct TranscriptTokenUsage: Sendable, Equatable {
        public let inputToday: Int
        public let outputToday: Int
        public let cacheToday: Int
        public let totalToday: Int
        public let tokens5H: Int
        public let tokens7D: Int
        public let turnsToday: Int
        public let sessionsToday: Int
    }

    public static func scanAntigravityTranscriptTokens(agyDir: String, now: Date = Date()) -> TranscriptTokenUsage {
        let fm = FileManager.default
        let startOfToday = Calendar.current.startOfDay(for: now)
        let fiveHoursAgo = now.addingTimeInterval(-18000)
        let sevenDaysAgo = now.addingTimeInterval(-604800)

        var candidateConvIDs: [String] = []
        var seenIDs = Set<String>()

        // Query all conversations modified within the last 7 days (using UTC cutoff so timezone never skews)
        let dbPath = "\(agyDir)/conversation_summaries.db"
        if fm.fileExists(atPath: dbPath) {
            let utcFmt = DateFormatter()
            utcFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            utcFmt.timeZone = TimeZone(secondsFromGMT: 0)
            let cutoffUTC = utcFmt.string(from: sevenDaysAgo.addingTimeInterval(-86400))

            let dbURI = "file://\(dbPath)?immutable=1"
            var db: OpaquePointer?
            if sqlite3_open_v2(dbURI, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK {
                let query = "SELECT conversation_id FROM conversation_summaries WHERE last_modified_time >= ? ORDER BY last_modified_time DESC LIMIT 120;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (cutoffUTC as NSString).utf8String, -1, nil)
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let cIDStr = sqlite3_column_text(stmt, 0) {
                            let cid = String(cString: cIDStr)
                            if seenIDs.insert(cid).inserted {
                                candidateConvIDs.append(cid)
                            }
                        }
                    }
                    sqlite3_finalize(stmt)
                }
                sqlite3_close(db)
            }
        }

        // Also scan brain directory by modification date so newly created transcripts not yet flushed to SQLite are included
        let brainDir = "\(agyDir)/brain"
        if let dirURLs = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: brainDir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for dirURL in dirURLs {
                let cid = dirURL.lastPathComponent
                guard !seenIDs.contains(cid) else { continue }
                let tURL = dirURL.appendingPathComponent(".system_generated/logs/transcript.jsonl")
                if let vals = try? tURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let mtime = vals.contentModificationDate,
                   mtime >= sevenDaysAgo {
                    seenIDs.insert(cid)
                    candidateConvIDs.append(cid)
                }
            }
        }

        var inputToday = 0
        var outputToday = 0
        var cacheToday = 0
        var tokens5H = 0
        var tokens7D = 0
        var turnsToday = 0
        var sessionsToday = 0

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        for cid in candidateConvIDs {
            let tPath = "\(brainDir)/\(cid)/.system_generated/logs/transcript.jsonl"
            guard let content = try? String(contentsOfFile: tPath, encoding: .utf8) else { continue }
            var hadTurnToday = false

            for line in content.split(separator: "\n") {
                guard line.contains("\"PLANNER_RESPONSE\"") else { continue }

                guard let lineDate = Self.parseCreatedAt(from: line, isoFrac: isoFrac, isoBasic: isoBasic) else {
                    continue
                }
                guard lineDate >= sevenDaysAgo else { continue }

                let (inp, out, cache) = Self.parseTokenCountsFromLine(line)
                let lineTotal = inp + out + cache

                tokens7D += lineTotal
                if lineDate >= fiveHoursAgo {
                    tokens5H += lineTotal
                }
                if lineDate >= startOfToday {
                    inputToday += inp
                    outputToday += out
                    cacheToday += cache
                    turnsToday += 1
                    hadTurnToday = true
                }
            }
            if hadTurnToday {
                sessionsToday += 1
            }
        }

        return TranscriptTokenUsage(
            inputToday: inputToday,
            outputToday: outputToday,
            cacheToday: cacheToday,
            totalToday: inputToday + outputToday + cacheToday,
            tokens5H: tokens5H,
            tokens7D: tokens7D,
            turnsToday: turnsToday,
            sessionsToday: sessionsToday
        )
    }

    public struct AntigravityLiveQuota: Sendable, Equatable {
        public let planTier: String?
        public let userAccount: String?
        public let activeModel: String?
        public let fiveHourQuota: AIWindowQuota?
        public let quotaPools: [AIQuotaPool]
        public let promptCreditsAvailable: Int?
        public let flowCreditsAvailable: Int?
    }

    private func queryAntigravityDaemon(agyDir: String) -> AntigravityLiveQuota? {
        let daemonDir = "\(agyDir)/daemon"
        let fm = FileManager.default
        guard let fileURLs = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: daemonDir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let hubFiles = fileURLs
            .filter { $0.lastPathComponent.hasPrefix("hub_") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let d1 = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }

        // Try live-PID hubs first, then fallback to newest hub files
        let orderedHubs = hubFiles.sorted { lhs, rhs in
            let alive1 = Self.isHubAlive(lhs)
            let alive2 = Self.isHubAlive(rhs)
            if alive1 != alive2 { return alive1 }
            return false
        }

        for hubURL in orderedHubs {
            guard let hubData = try? Data(contentsOf: hubURL),
                  let hubJson = try? JSONSerialization.jsonObject(with: hubData) as? [String: Any],
                  let port = hubJson["httpPort"] as? Int,
                  let csrf = hubJson["csrfToken"] as? String else { continue }

            guard let url = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else { continue }

            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.0)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
            req.httpBody = Data("{}".utf8)

            var responseData: Data? = nil
            let semaphore = DispatchSemaphore(value: 0)

            let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    responseData = data
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 1.1)

            if let data = responseData,
               let parsed = Self.parseAntigravityUserStatus(data: data) {
                return parsed
            }
        }
        return nil
    }

    private static func isHubAlive(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["pid"] as? Int, pid > 1 else {
            return false
        }
        return kill(pid_t(pid), 0) == 0
    }

    public static func parseAntigravityUserStatus(data: Data) -> AntigravityLiveQuota? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userStatus = json["userStatus"] as? [String: Any] else { return nil }

        let userName = userStatus["name"] as? String
        let email = userStatus["email"] as? String
        let userAcc = (userName != nil && email != nil) ? "\(userName!) (\(email!))" : (email ?? userName)

        var planTier: String? = nil
        if let tierObj = userStatus["userTier"] as? [String: Any], let tName = tierObj["name"] as? String {
            planTier = tName
        } else if let planStatus = userStatus["planStatus"] as? [String: Any],
                  let planInfo = planStatus["planInfo"] as? [String: Any],
                  let pName = planInfo["planName"] as? String {
            planTier = pName
        }

        var promptCredits: Int? = nil
        var flowCredits: Int? = nil
        if let planStatus = userStatus["planStatus"] as? [String: Any] {
            promptCredits = planStatus["availablePromptCredits"] as? Int
            flowCredits = planStatus["availableFlowCredits"] as? Int
        }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        var geminiLowestRemaining: Double? = nil
        var geminiResetDate: Date? = nil
        var geminiPrimaryLabel: String? = nil
        var geminiCount = 0

        var partnerLowestRemaining: Double? = nil
        var partnerResetDate: Date? = nil
        var partnerLabels: [String] = []

        if let cascadeData = userStatus["cascadeModelConfigData"] as? [String: Any],
           let configs = cascadeData["clientModelConfigs"] as? [[String: Any]] {
            for m in configs {
                guard let quotaInfo = m["quotaInfo"] as? [String: Any] else { continue }
                let label = m["label"] as? String ?? "Model"
                let remainingFraction = (quotaInfo["remainingFraction"] as? Double)
                    ?? (quotaInfo["remainingFraction"] as? NSNumber)?.doubleValue
                    ?? 1.0
                var resetDate: Date? = nil
                if let rTimeStr = quotaInfo["resetTime"] as? String {
                    resetDate = isoFrac.date(from: rTimeStr) ?? isoBasic.date(from: rTimeStr)
                }

                let lowerLabel = label.lowercased()
                let isPartner = lowerLabel.contains("claude") || lowerLabel.contains("gpt") || lowerLabel.contains("opus") || lowerLabel.contains("sonnet")

                if isPartner {
                    if !partnerLabels.contains(label) { partnerLabels.append(label) }
                    if partnerLowestRemaining == nil || remainingFraction < partnerLowestRemaining! {
                        partnerLowestRemaining = remainingFraction
                        partnerResetDate = resetDate
                    }
                } else {
                    geminiCount += 1
                    if geminiPrimaryLabel == nil { geminiPrimaryLabel = label }
                    if geminiLowestRemaining == nil || remainingFraction < geminiLowestRemaining! {
                        geminiLowestRemaining = remainingFraction
                        geminiResetDate = resetDate
                    }
                }
            }
        }

        var pools: [AIQuotaPool] = []

        if let rem = geminiLowestRemaining {
            let usedPct = max(0.0, min(100.0, (1.0 - rem) * 100.0))
            let q = AIWindowQuota(
                name: "Gemini Pool (5 Giờ)",
                windowSeconds: 18000,
                usedPercent: usedPct,
                resetAfterSeconds: geminiResetDate.map { max(0, Int($0.timeIntervalSinceNow)) },
                resetAt: geminiResetDate,
                note: "\(geminiCount) models • Hồi liên tục"
            )
            pools.append(AIQuotaPool(
                id: "agy-gemini",
                label: "Gemini 4 & 3.8 Flash",
                modelSummary: "\(geminiCount) cấu hình Gemini / Orchestrator",
                quota: q
            ))
        }

        if let rem = partnerLowestRemaining {
            let usedPct = max(0.0, min(100.0, (1.0 - rem) * 100.0))
            let shortSummary = partnerLabels.prefix(2).joined(separator: ", ")
            let q = AIWindowQuota(
                name: "Claude & Partner Pool (5 Giờ)",
                windowSeconds: 18000,
                usedPercent: usedPct,
                resetAfterSeconds: partnerResetDate.map { max(0, Int($0.timeIntervalSinceNow)) },
                resetAt: partnerResetDate,
                note: shortSummary
            )
            pools.append(AIQuotaPool(
                id: "agy-partner",
                label: "Claude 4.6 & GPT-OSS",
                modelSummary: shortSummary,
                quota: q
            ))
        }

        let primaryQuota = pools.first?.quota

        return AntigravityLiveQuota(
            planTier: planTier,
            userAccount: userAcc,
            activeModel: geminiPrimaryLabel ?? partnerLabels.first,
            fiveHourQuota: primaryQuota,
            quotaPools: pools,
            promptCreditsAvailable: promptCredits,
            flowCreditsAvailable: flowCredits
        )
    }

    // MARK: - OpenAI / ChatGPT Scanner
    public func scanOpenAICodex(home: String, today: String, referenceDate: Date = Date()) -> AIProviderMetrics {
        let codexDir = "\(home)/.codex"
        let fm = FileManager.default

        guard fm.fileExists(atPath: codexDir) else {
            return AIProviderMetrics(
                id: "chatgpt",
                name: "ChatGPT (OpenAI)",
                providerType: .openaiCodex,
                iconName: "bubble.left.and.bubble.right.fill",
                isDetected: false,
                statusMessage: "Chưa cài đặt (~/.codex)",
                sourceState: .offline
            )
        }

        var activeModel: String? = nil
        var userAccount: String? = nil
        var planTier: String? = nil
        var fiveHourQuota: AIWindowQuota? = nil
        var weeklyQuota: AIWindowQuota? = nil
        var resetCredits: Int? = nil
        var limitReached = false
        var sourceState: AIQuotaSourceState = .offline
        var lastSync = referenceDate
        var authExpired = false

        // Read local config.toml for configured model
        let configPath = "\(codexDir)/config.toml"
        if let configStr = try? String(contentsOfFile: configPath, encoding: .utf8) {
            for line in configStr.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("model =") {
                    let parts = trimmed.split(separator: "=")
                    if parts.count >= 2 {
                        activeModel = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    }
                }
            }
        }

        // Read local Codex SQLite threads for real token consumption (Today / 5h / 7d)
        let codexTokens = Self.scanCodexSQLiteTokens(codexDir: codexDir, now: referenceDate)
        if activeModel == nil, let latestModel = codexTokens.latestModel {
            activeModel = latestModel
        }

        // Read auth.json for access token and query /wham/usage
        let authPath = "\(codexDir)/auth.json"
        if let authData = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
           let authJson = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
           let tokens = authJson["tokens"] as? [String: Any],
           let accessToken = tokens["access_token"] as? String {
            let accountId = tokens["account_id"] as? String ?? ""

            let fetchRes = queryChatGPTBackendUsage(accessToken: accessToken, accountId: accountId)
            switch fetchRes {
            case .success(let liveUsage):
                planTier = liveUsage.planTier
                userAccount = liveUsage.email
                fiveHourQuota = liveUsage.fiveHourQuota
                weeklyQuota = liveUsage.weeklyQuota
                resetCredits = liveUsage.resetCreditsAvailable
                limitReached = liveUsage.limitReached
                sourceState = .live
                lastSync = referenceDate

                saveCache { store in
                    store.chatGPT = CachedAIQuotaStore.CachedProviderQuota(
                        savedAt: referenceDate,
                        planTier: planTier,
                        userAccount: userAccount,
                        activeModel: activeModel,
                        fiveHourQuota: fiveHourQuota,
                        weeklyQuota: weeklyQuota,
                        quotaPools: [],
                        promptCreditsAvailable: nil,
                        flowCreditsAvailable: nil,
                        resetCreditsAvailable: resetCredits,
                        limitReached: limitReached
                    )
                }
            case .unauthorized:
                authExpired = true
            case .networkError:
                break
            }
        }

        // NEVER fabricate fake percentages (like old hardcoded 20%). Use verified cache if available.
        if sourceState != .live, let cached = loadCache().chatGPT {
            planTier = cached.planTier
            userAccount = cached.userAccount
            activeModel = activeModel ?? cached.activeModel
            fiveHourQuota = cached.fiveHourQuota
            weeklyQuota = cached.weeklyQuota
            resetCredits = cached.resetCreditsAvailable
            limitReached = cached.limitReached
            sourceState = .cached
            lastSync = cached.savedAt
        }

        let status: String
        switch sourceState {
        case .live:
            status = userAccount != nil ? "Kết nối trực tiếp • \(userAccount!)" : "Đã đồng bộ trực tiếp"
        case .cached:
            status = authExpired
                ? "Token Codex hết hạn • Đang hiện dữ liệu lưu gần nhất"
                : "Mất kết nối mạng • Đang hiện dữ liệu lưu gần nhất"
        case .offline:
            status = authExpired
                ? "Phiên ChatGPT hết hạn — mở Codex để làm mới token"
                : "Không thể kết nối ChatGPT API"
        }

        return AIProviderMetrics(
            id: "chatgpt",
            name: "ChatGPT (OpenAI)",
            providerType: .openaiCodex,
            iconName: "bubble.left.and.bubble.right.fill",
            isDetected: true,
            statusMessage: status,
            activeModel: activeModel ?? "Codex",
            userAccount: userAccount ?? "ChatGPT Account",
            planTier: planTier ?? "ChatGPT",
            fiveHourQuota: fiveHourQuota,
            weeklyQuota: weeklyQuota,
            quotaPools: [],
            sourceState: sourceState,
            resetCreditsAvailable: resetCredits,
            limitReached: limitReached,
            totalTokensToday: codexTokens.tokensToday,
            tokensLast5Hours: codexTokens.tokens5H,
            tokensLast7Days: codexTokens.tokens7D,
            activeSessionsToday: codexTokens.sessionsToday,
            lastSyncTime: lastSync
        )
    }

    public struct CodexTokenUsage: Sendable, Equatable {
        public let tokensToday: Int
        public let tokens5H: Int
        public let tokens7D: Int
        public let sessionsToday: Int
        public let latestModel: String?
    }

    public static func scanCodexSQLiteTokens(codexDir: String, now: Date = Date()) -> CodexTokenUsage {
        let fm = FileManager.default
        let dbPath = "\(codexDir)/state_5.sqlite"
        guard fm.fileExists(atPath: dbPath) else {
            return CodexTokenUsage(tokensToday: 0, tokens5H: 0, tokens7D: 0, sessionsToday: 0, latestModel: nil)
        }

        let startOfTodayEpoch = Int64(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        let fiveHoursAgoEpoch = Int64(now.addingTimeInterval(-18000).timeIntervalSince1970)
        let sevenDaysAgoEpoch = Int64(now.addingTimeInterval(-604800).timeIntervalSince1970)

        var tokensToday = 0
        var tokens5H = 0
        var tokens7D = 0
        var sessionsToday = 0
        var latestModel: String? = nil

        let dbURI = "file://\(dbPath)?immutable=1"
        var db: OpaquePointer?
        if sqlite3_open_v2(dbURI, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK {
            let query = "SELECT updated_at, tokens_used, model FROM threads WHERE updated_at >= ? ORDER BY updated_at DESC LIMIT 200;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, sevenDaysAgoEpoch)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let updatedAt = sqlite3_column_int64(stmt, 0)
                    let used = Int(sqlite3_column_int64(stmt, 1))
                    if latestModel == nil, let mPtr = sqlite3_column_text(stmt, 2) {
                        let m = String(cString: mPtr).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !m.isEmpty { latestModel = m }
                    }
                    guard used > 0 else { continue }
                    tokens7D += used
                    if updatedAt >= fiveHoursAgoEpoch {
                        tokens5H += used
                    }
                    if updatedAt >= startOfTodayEpoch {
                        tokensToday += used
                        sessionsToday += 1
                    }
                }
                sqlite3_finalize(stmt)
            }
            sqlite3_close(db)
        }

        return CodexTokenUsage(
            tokensToday: tokensToday,
            tokens5H: tokens5H,
            tokens7D: tokens7D,
            sessionsToday: sessionsToday,
            latestModel: latestModel
        )
    }

    private struct ChatGPTLiveUsage {
        let email: String?
        let planTier: String
        let fiveHourQuota: AIWindowQuota?
        let weeklyQuota: AIWindowQuota?
        let resetCreditsAvailable: Int?
        let limitReached: Bool
    }

    private enum ChatGPTFetchResult {
        case success(ChatGPTLiveUsage)
        case unauthorized
        case networkError
    }

    private func queryChatGPTBackendUsage(accessToken: String, accountId: String) -> ChatGPTFetchResult {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return .networkError }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.5)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if !accountId.isEmpty {
            req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        req.setValue("chatgpt", forHTTPHeaderField: "OAI-App-Brand")
        req.setValue("1", forHTTPHeaderField: "x-openai-codex-pricing-chooser")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6_0)", forHTTPHeaderField: "User-Agent")

        var responseData: Data? = nil
        var statusCode: Int = 0
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let httpResp = resp as? HTTPURLResponse {
                statusCode = httpResp.statusCode
                if httpResp.statusCode == 200 {
                    responseData = data
                }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.7)

        if statusCode == 401 || statusCode == 403 {
            return .unauthorized
        }

        guard let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .networkError
        }

        let email = json["email"] as? String
        let rawPlan = json["plan_type"] as? String ?? "plus"
        let planName: String = {
            switch rawPlan.lowercased() {
            case "pro": return "ChatGPT Pro"
            case "team": return "ChatGPT Team"
            case "enterprise": return "ChatGPT Enterprise"
            case "free": return "ChatGPT Free"
            default: return "ChatGPT Plus"
            }
        }()

        var fiveHour: AIWindowQuota? = nil
        var weekly: AIWindowQuota? = nil
        var limitReached = false

        if let rateLimit = json["rate_limit"] as? [String: Any] {
            limitReached = (rateLimit["limit_reached"] as? Bool) ?? false

            if let primary = rateLimit["primary_window"] as? [String: Any] {
                let usedPercent = (primary["used_percent"] as? Double)
                    ?? (primary["used_percent"] as? NSNumber)?.doubleValue
                    ?? 0.0
                let winSecs = primary["limit_window_seconds"] as? Int ?? 18000
                let resetAfter = primary["reset_after_seconds"] as? Int
                var resetAtDate: Date? = nil
                if let resetEpoch = (primary["reset_at"] as? TimeInterval) ?? (primary["reset_at"] as? NSNumber)?.doubleValue {
                    resetAtDate = Date(timeIntervalSince1970: resetEpoch)
                }

                fiveHour = AIWindowQuota(
                    name: "Phiên 5 Giờ (Primary)",
                    windowSeconds: winSecs,
                    usedPercent: usedPercent,
                    resetAfterSeconds: resetAfter,
                    resetAt: resetAtDate,
                    note: "Hạn mức burst 5 giờ"
                )
            }

            if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                let usedPercent = (secondary["used_percent"] as? Double)
                    ?? (secondary["used_percent"] as? NSNumber)?.doubleValue
                    ?? 0.0
                let winSecs = secondary["limit_window_seconds"] as? Int ?? 604800
                let resetAfter = secondary["reset_after_seconds"] as? Int
                var resetAtDate: Date? = nil
                if let resetEpoch = (secondary["reset_at"] as? TimeInterval) ?? (secondary["reset_at"] as? NSNumber)?.doubleValue {
                    resetAtDate = Date(timeIntervalSince1970: resetEpoch)
                }

                weekly = AIWindowQuota(
                    name: "Giới Hạn Tuần (7 Ngày)",
                    windowSeconds: winSecs,
                    usedPercent: usedPercent,
                    resetAfterSeconds: resetAfter,
                    resetAt: resetAtDate,
                    note: "Hạn mức định kỳ tuần"
                )
            }
        }

        var resetCredits: Int? = nil
        if let rc = json["rate_limit_reset_credits"] as? [String: Any],
           let avail = rc["available_count"] as? Int {
            resetCredits = avail
        }

        return .success(ChatGPTLiveUsage(
            email: email,
            planTier: planName,
            fiveHourQuota: fiveHour,
            weeklyQuota: weekly,
            resetCreditsAvailable: resetCredits,
            limitReached: limitReached
        ))
    }

    // MARK: - Other AI tools (Preserved for compatibility)
    public func scanCommandCode(home: String, today: String) -> AIProviderMetrics {
        let ccDir = "\(home)/.commandcode"
        let fm = FileManager.default
        guard fm.fileExists(atPath: ccDir) else {
            return AIProviderMetrics(
                id: "commandcode",
                name: "CommandCode AI",
                providerType: .commandcode,
                iconName: "terminal.fill",
                isDetected: false,
                statusMessage: "Chưa cài đặt (~/.commandcode)",
                sourceState: .offline
            )
        }
        return AIProviderMetrics(
            id: "commandcode",
            name: "CommandCode AI",
            providerType: .commandcode,
            iconName: "terminal.fill",
            isDetected: true,
            statusMessage: "Đã cài đặt",
            activeModel: "Claude 3.7",
            userAccount: "@commandcode",
            sourceState: .live
        )
    }

    public func scanClaudeCode(home: String) -> AIProviderMetrics {
        let claudePath = "\(home)/.claude.json"
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudePath) else {
            return AIProviderMetrics(
                id: "claude",
                name: "Claude Code",
                providerType: .claude,
                iconName: "sparkles",
                isDetected: false,
                statusMessage: "Chưa cài đặt (~/.claude.json)",
                sourceState: .offline
            )
        }
        return AIProviderMetrics(
            id: "claude",
            name: "Claude Code",
            providerType: .claude,
            iconName: "sparkles",
            isDetected: true,
            statusMessage: "Đã kết nối",
            activeModel: "Claude Sonnet",
            userAccount: "Anthropic Claude",
            sourceState: .live
        )
    }

    private static func parseCreatedAt(from line: Substring, isoFrac: ISO8601DateFormatter, isoBasic: ISO8601DateFormatter) -> Date? {
        guard let range = line.range(of: "\"created_at\":\"") ?? line.range(of: "\"created_at\": \"") else {
            return nil
        }
        let sub = line[range.upperBound...]
        guard let endR = sub.range(of: "\"") else { return nil }
        let dateStr = String(sub[..<endR.lowerBound])
        return isoFrac.date(from: dateStr) ?? isoBasic.date(from: dateStr)
    }

    private static func parseTokenCountsFromLine(_ line: Substring) -> (Int, Int, Int) {
        var inputT = 0
        var outputT = 0
        var cacheT = 0

        if let range = line.range(of: "\"input_tokens\":") ?? line.range(of: "\"input_tokens\": ") {
            let sub = line[range.upperBound...].drop(while: { $0 == " " })
            inputT = Int(sub.prefix(while: { $0.isNumber })) ?? 0
        }
        if let range = line.range(of: "\"output_tokens\":") ?? line.range(of: "\"output_tokens\": ") {
            let sub = line[range.upperBound...].drop(while: { $0 == " " })
            outputT = Int(sub.prefix(while: { $0.isNumber })) ?? 0
        }
        if let range = line.range(of: "\"cache_read_tokens\":") ?? line.range(of: "\"cache_read_tokens\": ") {
            let sub = line[range.upperBound...].drop(while: { $0 == " " })
            cacheT = Int(sub.prefix(while: { $0.isNumber })) ?? 0
        }
        return (inputT, outputT, cacheT)
    }
}
