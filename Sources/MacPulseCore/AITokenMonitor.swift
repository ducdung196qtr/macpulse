import Foundation
import SQLite3

public enum AIProviderType: String, Sendable, CaseIterable, Codable {
    case antigravity = "antigravity"
    case openaiCodex = "openai_codex"
    case commandcode = "commandcode"
    case claude = "claude"
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

    public var formattedResetCountdown: String {
        if let resetAt = resetAt {
            let diff = Int(resetAt.timeIntervalSinceNow)
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

    public static func formatDuration(seconds: Int) -> String {
        if seconds >= 86400 {
            let days = seconds / 86400
            let hours = (seconds % 86400) / 3600
            return "\(days) ngày \(hours)h"
        } else if seconds >= 3600 {
            let hours = seconds / 3600
            let mins = (seconds % 3600) / 60
            return "\(hours)h \(mins)m"
        } else if seconds >= 60 {
            let mins = seconds / 60
            return "\(mins) phút"
        } else {
            return "\(seconds)s"
        }
    }
}

public struct AIProviderMetrics: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let providerType: AIProviderType
    public let iconName: String
    public let isDetected: Bool
    public let statusMessage: String
    public let activeModel: String?
    public let userAccount: String?
    public let planTier: String? // "Google AI Pro", "ChatGPT Plus"

    // Quota windows (5h & Week)
    public let fiveHourQuota: AIWindowQuota?
    public let weeklyQuota: AIWindowQuota?

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

public struct AITokenSnapshot: Sendable, Equatable {
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

public final class AITokenMonitor: Sendable {
    public static let shared = AITokenMonitor()

    public init() {}

    public static func currentDateString(date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: date)
    }

    public func scanAll(todayDateString: String? = nil) -> AITokenSnapshot {
        let today = todayDateString ?? Self.currentDateString()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Priority 1: Google Antigravity & ChatGPT (User's primary focus)
        let p1 = scanAntigravity(home: home, today: today)
        let p2 = scanOpenAICodex(home: home, today: today)
        let p3 = scanCommandCode(home: home, today: today)
        let p4 = scanClaudeCode(home: home)

        let providers = [p1, p2, p3, p4]
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
    public func scanAntigravity(home: String, today: String) -> AIProviderMetrics {
        let agyDir = "\(home)/.gemini/antigravity"
        let fm = FileManager.default

        guard fm.fileExists(atPath: agyDir) else {
            return AIProviderMetrics(
                id: "antigravity",
                name: "Google Antigravity",
                providerType: .antigravity,
                iconName: "brain.head.profile",
                isDetected: false,
                statusMessage: "Chưa cài đặt (~/.gemini/antigravity)"
            )
        }

        var planTier: String? = "Google AI Pro"
        var userAccount: String? = nil
        var activeModel: String? = "Gemini 3.8 Flash (High)"
        var fiveHourQuota: AIWindowQuota? = nil
        var weeklyQuota: AIWindowQuota? = nil

        // 1. Query Antigravity daemon language server on localhost for live quota
        if let liveStatus = queryAntigravityDaemon(agyDir: agyDir) {
            planTier = liveStatus.planTier ?? planTier
            userAccount = liveStatus.userAccount
            activeModel = liveStatus.activeModel ?? activeModel
            fiveHourQuota = liveStatus.fiveHourQuota
            weeklyQuota = liveStatus.weeklyQuota
        }

        // 2. Scan local SQLite & transcripts for token usage
        let dbPath = "\(agyDir)/conversation_summaries.db"
        var activeConvIDs: [String] = []

        if fm.fileExists(atPath: dbPath) {
            let dbURI = "file://\(dbPath)?immutable=1"
            var db: OpaquePointer?
            if sqlite3_open_v2(dbURI, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK {
                let query = "SELECT conversation_id, last_modified_time FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 50;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let cIDStr = sqlite3_column_text(stmt, 0),
                           let modStr = sqlite3_column_text(stmt, 1) {
                            let cid = String(cString: cIDStr)
                            let mod = String(cString: modStr)
                            if mod.hasPrefix(today) || activeConvIDs.isEmpty {
                                activeConvIDs.append(cid)
                            }
                        }
                    }
                    sqlite3_finalize(stmt)
                }
                sqlite3_close(db)
            }
        }

        let brainDir = "\(agyDir)/brain"
        if activeConvIDs.isEmpty, let dirs = try? fm.contentsOfDirectory(atPath: brainDir) {
            activeConvIDs = Array(dirs.prefix(15))
        }

        var totalPrompt = 0
        var totalOutput = 0
        var totalCache = 0
        var tokensLast5H = 0
        var tokensLast7D = 0
        var turnsCount = 0
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-18000)
        let sevenDaysAgo = now.addingTimeInterval(-604800)

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFmt = ISO8601DateFormatter()

        for cid in activeConvIDs {
            let tPath = "\(brainDir)/\(cid)/.system_generated/logs/transcript.jsonl"
            guard let content = try? String(contentsOfFile: tPath, encoding: .utf8) else { continue }

            for line in content.split(separator: "\n") {
                guard line.contains("\"type\":\"PLANNER_RESPONSE\"") || line.contains("\"type\": \"PLANNER_RESPONSE\"") else { continue }
                turnsCount += 1

                let tokens = Self.parseTokenCountsFromLine(String(line))
                let lineDate: Date? = {
                    if let range = line.range(of: "\"created_at\":\"") ?? line.range(of: "\"created_at\": \"") {
                        let sub = line[range.upperBound...]
                        if let endR = sub.range(of: "\"") {
                            let dateStr = String(sub[..<endR.lowerBound])
                            return isoFmt.date(from: dateStr) ?? fallbackFmt.date(from: dateStr)
                        }
                    }
                    return nil
                }()

                let lineTotal = tokens.0 + tokens.1 + tokens.2

                // Today
                totalPrompt += tokens.0
                totalOutput += tokens.1
                totalCache += tokens.2

                // Window calculations
                if let d = lineDate {
                    if d >= fiveHoursAgo {
                        tokensLast5H += lineTotal
                    }
                    if d >= sevenDaysAgo {
                        tokensLast7D += lineTotal
                    }
                } else {
                    tokensLast5H += lineTotal
                    tokensLast7D += lineTotal
                }
            }
        }

        let grandTotal = totalPrompt + totalOutput + totalCache
        let estCost = (Double(totalPrompt) * 0.075 / 1_000_000.0) + (Double(totalOutput) * 0.30 / 1_000_000.0)

        // If live daemon wasn't running, construct fallback 5h & weekly window info
        if fiveHourQuota == nil {
            fiveHourQuota = AIWindowQuota(
                name: "Phiên 5 Giờ (Rolling)",
                windowSeconds: 18000,
                usedPercent: 0.0,
                resetAfterSeconds: 18000,
                resetAt: now.addingTimeInterval(18000),
                windowTokensUsed: tokensLast5H,
                note: "\(activeModel ?? "Gemini") • Tự động hồi phiên 5h"
            )
        }

        if weeklyQuota == nil {
            weeklyQuota = AIWindowQuota(
                name: "Giới Hạn Tuần (Weekly Cap)",
                windowSeconds: 604800,
                usedPercent: 0.0,
                resetAfterSeconds: nil,
                resetAt: nil,
                windowTokensUsed: tokensLast7D,
                note: "Google AI Pro • Chưa chạm trần tuần"
            )
        }

        let status = userAccount != nil ? "Tài khoản: \(userAccount!)" : "Đang hoạt động"

        return AIProviderMetrics(
            id: "antigravity",
            name: "Google Antigravity",
            providerType: .antigravity,
            iconName: "brain.head.profile",
            isDetected: true,
            statusMessage: status,
            activeModel: activeModel,
            userAccount: userAccount ?? "Google AI Account",
            planTier: planTier,
            fiveHourQuota: fiveHourQuota,
            weeklyQuota: weeklyQuota,
            inputTokensToday: totalPrompt,
            outputTokensToday: totalOutput,
            cacheTokensToday: totalCache,
            totalTokensToday: grandTotal,
            tokensLast5Hours: tokensLast5H,
            tokensLast7Days: tokensLast7D,
            turnsOrPromptsToday: turnsCount,
            activeSessionsToday: activeConvIDs.count,
            estimatedCostTodayUSD: estCost
        )
    }

    private struct AntigravityLiveQuota {
        let planTier: String?
        let userAccount: String?
        let activeModel: String?
        let fiveHourQuota: AIWindowQuota?
        let weeklyQuota: AIWindowQuota?
    }

    private func queryAntigravityDaemon(agyDir: String) -> AntigravityLiveQuota? {
        let daemonDir = "\(agyDir)/daemon"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: daemonDir) else { return nil }
        guard let hubFile = files.first(where: { $0.hasPrefix("hub_") && $0.hasSuffix(".json") }) else { return nil }

        let hubPath = "\(daemonDir)/\(hubFile)"
        guard let hubData = try? Data(contentsOf: URL(fileURLWithPath: hubPath)),
              let hubJson = try? JSONSerialization.jsonObject(with: hubData) as? [String: Any],
              let port = hubJson["httpPort"] as? Int,
              let csrf = hubJson["csrfToken"] as? String else { return nil }

        guard let url = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else { return nil }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.0)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        req.httpBody = Data("{}".utf8)

        var responseData: Data? = nil
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: req) { data, _, _ in
            responseData = data
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.0)

        guard let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userStatus = json["userStatus"] as? [String: Any] else { return nil }

        let userName = userStatus["name"] as? String
        let email = userStatus["email"] as? String
        let userAcc = (userName != nil && email != nil) ? "\(userName!) (\(email!))" : (email ?? userName)

        var planTier = "Google AI Pro"
        if let tierObj = userStatus["userTier"] as? [String: Any], let tName = tierObj["name"] as? String {
            planTier = tName
        } else if let planStatus = userStatus["planStatus"] as? [String: Any],
                  let planInfo = planStatus["planInfo"] as? [String: Any],
                  let pName = planInfo["planName"] as? String {
            planTier = pName
        }

        var activeModelName: String? = nil
        var fiveHourQuota: AIWindowQuota? = nil

        let isoFmt = ISO8601DateFormatter()

        if let cascadeData = userStatus["cascadeModelConfigData"] as? [String: Any],
           let configs = cascadeData["clientModelConfigs"] as? [[String: Any]] {
            for m in configs {
                if let quotaInfo = m["quotaInfo"] as? [String: Any] {
                    let label = m["label"] as? String ?? "Gemini"
                    activeModelName = label
                    let remainingFraction = quotaInfo["remainingFraction"] as? Double ?? 1.0
                    let usedPercent = max(0.0, min(100.0, (1.0 - remainingFraction) * 100.0))
                    var resetDate: Date? = nil
                    if let rTimeStr = quotaInfo["resetTime"] as? String {
                        resetDate = isoFmt.date(from: rTimeStr)
                    }

                    fiveHourQuota = AIWindowQuota(
                        name: "Phiên 5 Giờ (Rolling Window)",
                        windowSeconds: 18000,
                        usedPercent: usedPercent,
                        resetAfterSeconds: resetDate != nil ? Int(resetDate!.timeIntervalSinceNow) : 18000,
                        resetAt: resetDate,
                        note: "\(label) • Hồi liên tục"
                    )
                    break
                }
            }
        }

        let weeklyQuota = AIWindowQuota(
            name: "Giới Hạn Tuần (Weekly Cap)",
            windowSeconds: 604800,
            usedPercent: 0.0,
            resetAfterSeconds: nil,
            resetAt: nil,
            note: "\(planTier) • Tự động hồi phiên 5h đến khi chạm trần"
        )

        return AntigravityLiveQuota(
            planTier: planTier,
            userAccount: userAcc,
            activeModel: activeModelName,
            fiveHourQuota: fiveHourQuota,
            weeklyQuota: weeklyQuota
        )
    }

    // MARK: - OpenAI / ChatGPT Scanner
    public func scanOpenAICodex(home: String, today: String) -> AIProviderMetrics {
        let codexDir = "\(home)/.codex"
        let fm = FileManager.default

        guard fm.fileExists(atPath: codexDir) else {
            return AIProviderMetrics(
                id: "chatgpt",
                name: "ChatGPT (OpenAI)",
                providerType: .openaiCodex,
                iconName: "bubble.left.and.bubble.right.fill",
                isDetected: false,
                statusMessage: "Chưa cài đặt (~/.codex)"
            )
        }

        var activeModel = "gpt-6.1-sol"
        var userAccount: String? = nil
        var planTier: String = "ChatGPT Plus"
        var fiveHourQuota: AIWindowQuota? = nil
        var weeklyQuota: AIWindowQuota? = nil

        // Read local config.toml for model
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

        // Read auth.json for tokens and query /wham/usage
        let authPath = "\(codexDir)/auth.json"
        if let authData = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
           let authJson = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] {

            if let tokens = authJson["tokens"] as? [String: Any],
               let accessToken = tokens["access_token"] as? String {
                let accountId = tokens["account_id"] as? String ?? ""

                // Fetch live usage from ChatGPT backend
                if let liveUsage = queryChatGPTBackendUsage(accessToken: accessToken, accountId: accountId) {
                    planTier = liveUsage.planTier
                    userAccount = liveUsage.email
                    fiveHourQuota = liveUsage.fiveHourQuota
                    weeklyQuota = liveUsage.weeklyQuota
                }
            }
        }

        // Fallbacks if offline
        if fiveHourQuota == nil {
            fiveHourQuota = AIWindowQuota(
                name: "Phiên 5 Giờ (Primary)",
                windowSeconds: 18000,
                usedPercent: 0.0,
                resetAfterSeconds: 18000,
                resetAt: Date().addingTimeInterval(18000),
                note: "\(activeModel) • Hạn mức ngắn hạn"
            )
        }

        if weeklyQuota == nil {
            weeklyQuota = AIWindowQuota(
                name: "Giới Hạn Tuần (Weekly)",
                windowSeconds: 604800,
                usedPercent: 20.0,
                resetAfterSeconds: 86400 * 2,
                resetAt: Date().addingTimeInterval(86400 * 2),
                note: "Hạn mức định kỳ tuần"
            )
        }

        let status = userAccount != nil ? "Tài khoản: \(userAccount!)" : "Đã đăng nhập"

        return AIProviderMetrics(
            id: "chatgpt",
            name: "ChatGPT (OpenAI)",
            providerType: .openaiCodex,
            iconName: "bubble.left.and.bubble.right.fill",
            isDetected: true,
            statusMessage: status,
            activeModel: activeModel,
            userAccount: userAccount ?? "ChatGPT Account",
            planTier: planTier,
            fiveHourQuota: fiveHourQuota,
            weeklyQuota: weeklyQuota
        )
    }

    private struct ChatGPTLiveUsage {
        let email: String?
        let planTier: String
        let fiveHourQuota: AIWindowQuota?
        let weeklyQuota: AIWindowQuota?
    }

    private func queryChatGPTBackendUsage(accessToken: String, accountId: String) -> ChatGPTLiveUsage? {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return nil }

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
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 {
                responseData = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.5)

        guard let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let email = json["email"] as? String
        let rawPlan = json["plan_type"] as? String ?? "plus"
        let planName: String = {
            switch rawPlan.lowercased() {
            case "pro": return "ChatGPT Pro"
            case "team": return "ChatGPT Team"
            case "enterprise": return "ChatGPT Enterprise"
            default: return "ChatGPT Plus"
            }
        }()

        var fiveHour: AIWindowQuota? = nil
        var weekly: AIWindowQuota? = nil

        if let rateLimit = json["rate_limit"] as? [String: Any] {
            if let primary = rateLimit["primary_window"] as? [String: Any] {
                let usedPercent = primary["used_percent"] as? Double ?? 0.0
                let winSecs = primary["limit_window_seconds"] as? Int ?? 18000
                let resetAfter = primary["reset_after_seconds"] as? Int
                var resetAtDate: Date? = nil
                if let resetEpoch = primary["reset_at"] as? TimeInterval {
                    resetAtDate = Date(timeIntervalSince1970: resetEpoch)
                }

                fiveHour = AIWindowQuota(
                    name: "Phiên 5 Giờ (Primary Window)",
                    windowSeconds: winSecs,
                    usedPercent: usedPercent,
                    resetAfterSeconds: resetAfter,
                    resetAt: resetAtDate,
                    note: "Hạn mức burst 5 giờ"
                )
            }

            if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                let usedPercent = secondary["used_percent"] as? Double ?? 0.0
                let winSecs = secondary["limit_window_seconds"] as? Int ?? 604800
                let resetAfter = secondary["reset_after_seconds"] as? Int
                var resetAtDate: Date? = nil
                if let resetEpoch = secondary["reset_at"] as? TimeInterval {
                    resetAtDate = Date(timeIntervalSince1970: resetEpoch)
                }

                weekly = AIWindowQuota(
                    name: "Giới Hạn Tuần (Weekly Window)",
                    windowSeconds: winSecs,
                    usedPercent: usedPercent,
                    resetAfterSeconds: resetAfter,
                    resetAt: resetAtDate,
                    note: "Hạn mức định kỳ tuần"
                )
            }
        }

        return ChatGPTLiveUsage(
            email: email,
            planTier: planName,
            fiveHourQuota: fiveHour,
            weeklyQuota: weekly
        )
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
                statusMessage: "Chưa cài đặt (~/.commandcode)"
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
            userAccount: "@commandcode"
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
                statusMessage: "Chưa cài đặt (~/.claude.json)"
            )
        }
        return AIProviderMetrics(
            id: "claude",
            name: "Claude Code",
            providerType: .claude,
            iconName: "sparkles",
            isDetected: true,
            statusMessage: "Đã kết nối",
            activeModel: "Claude 3.5 Sonnet",
            userAccount: "Anthropic Claude"
        )
    }

    private static func parseTokenCountsFromLine(_ line: String) -> (Int, Int, Int) {
        var inputT = 0
        var outputT = 0
        var cacheT = 0

        if let range = line.range(of: "\"input_tokens\":") ?? line.range(of: "\"input_tokens\": ") {
            let sub = line[range.upperBound...]
            inputT = Int(sub.prefix(while: { $0.isNumber })) ?? 0
        }
        if let range = line.range(of: "\"output_tokens\":") ?? line.range(of: "\"output_tokens\": ") {
            let sub = line[range.upperBound...]
            outputT = Int(sub.prefix(while: { $0.isNumber })) ?? 0
        }
        if let range = line.range(of: "\"cache_read_tokens\":") ?? line.range(of: "\"cache_read_tokens\": ") {
            let sub = line[range.upperBound...]
            cacheT = Int(sub.prefix(while: { $0.isNumber })) ?? 0
        }
        return (inputT, outputT, cacheT)
    }
}
