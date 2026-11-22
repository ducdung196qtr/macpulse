import Foundation
import SQLite3

public enum AIProviderType: String, Sendable, CaseIterable, Codable {
    case antigravity = "antigravity"
    case openaiCodex = "openai_codex"
    case commandcode = "commandcode"
    case claude = "claude"
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

    // Token metrics today
    public let inputTokensToday: Int
    public let outputTokensToday: Int
    public let cacheTokensToday: Int
    public let totalTokensToday: Int

    // Activity counts
    public let turnsOrPromptsToday: Int
    public let activeSessionsToday: Int

    // Cost / Balance
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
        inputTokensToday: Int = 0,
        outputTokensToday: Int = 0,
        cacheTokensToday: Int = 0,
        totalTokensToday: Int = 0,
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
        self.inputTokensToday = inputTokensToday
        self.outputTokensToday = outputTokensToday
        self.cacheTokensToday = cacheTokensToday
        self.totalTokensToday = totalTokensToday
        self.turnsOrPromptsToday = turnsOrPromptsToday
        self.activeSessionsToday = activeSessionsToday
        self.estimatedCostTodayUSD = estimatedCostTodayUSD
        self.remainingBalanceUSD = remainingBalanceUSD
        self.lastSyncTime = lastSyncTime
    }

    public var formattedTokensToday: String {
        Self.formatTokenNumber(totalTokensToday)
    }

    public var formattedInputTokens: String {
        Self.formatTokenNumber(inputTokensToday)
    }

    public var formattedOutputTokens: String {
        Self.formatTokenNumber(outputTokensToday)
    }

    public var formattedCacheTokens: String {
        Self.formatTokenNumber(cacheTokensToday)
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

        let dbPath = "\(agyDir)/conversation_summaries.db"
        var activeConvIDs: [String] = []

        if fm.fileExists(atPath: dbPath) {
            let dbURI = "file://\(dbPath)?immutable=1"
            var db: OpaquePointer?
            if sqlite3_open_v2(dbURI, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK {
                // Fetch recent conversation IDs from today
                let query = "SELECT conversation_id, last_modified_time FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 40;"
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

        // If no conversations found via DB, check brain directory directly
        let brainDir = "\(agyDir)/brain"
        if activeConvIDs.isEmpty, let dirs = try? fm.contentsOfDirectory(atPath: brainDir) {
            activeConvIDs = Array(dirs.prefix(15))
        }

        var totalIn = 0
        var totalOut = 0
        var totalCache = 0
        var turnsToday = 0
        var sessionsCount = 0

        for convID in activeConvIDs {
            let transcriptPath = "\(brainDir)/\(convID)/.system_generated/logs/transcript.jsonl"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: transcriptPath)),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            var sessionHadTurns = false
            for line in content.split(separator: "\n") {
                // Fast pre-filter: skip lines without model response
                guard line.contains("\"PLANNER_RESPONSE\"") else { continue }
                guard let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }

                let createdAt = json["created_at"] as? String ?? ""
                if createdAt.hasPrefix(today) {
                    turnsToday += 1
                    sessionHadTurns = true
                    totalIn += json["input_tokens"] as? Int ?? 0
                    totalOut += json["output_tokens"] as? Int ?? 0
                    totalCache += json["cache_read_tokens"] as? Int ?? 0
                }
            }
            if sessionHadTurns {
                sessionsCount += 1
            }
        }

        let totalTokens = totalIn + totalOut + totalCache
        // Gemini standard API estimate (Input $1.25/M, Output $5.00/M, Cache $0.30/M)
        let estCost = (Double(totalIn) * 1.25 + Double(totalOut) * 5.00 + Double(totalCache) * 0.30) / 1_000_000.0

        return AIProviderMetrics(
            id: "antigravity",
            name: "Google Antigravity",
            providerType: .antigravity,
            iconName: "brain.head.profile",
            isDetected: true,
            statusMessage: "Đang hoạt động (\(sessionsCount) phiên hôm nay)",
            activeModel: "Gemini 2.5 / 3.0",
            userAccount: "Google DeepMind",
            inputTokensToday: totalIn,
            outputTokensToday: totalOut,
            cacheTokensToday: totalCache,
            totalTokensToday: totalTokens,
            turnsOrPromptsToday: turnsToday,
            activeSessionsToday: sessionsCount,
            estimatedCostTodayUSD: estCost
        )
    }

    public func scanOpenAICodex(home: String, today: String) -> AIProviderMetrics {
        let codexDir = "\(home)/.codex"
        let fm = FileManager.default

        guard fm.fileExists(atPath: codexDir) else {
            return AIProviderMetrics(
                id: "openai_codex",
                name: "OpenAI / Codex",
                providerType: .openaiCodex,
                iconName: "cpu",
                isDetected: false,
                statusMessage: "Chưa cấu hình (~/.codex)"
            )
        }

        var detectedModel = "gpt-6.1-sol"
        var serviceTier = "default"
        var hasApiKey = false

        let configPath = "\(codexDir)/config.toml"
        if let configStr = try? String(contentsOfFile: configPath, encoding: .utf8) {
            for line in configStr.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("model =") {
                    let parts = trimmed.split(separator: "=")
                    if parts.count >= 2 {
                        detectedModel = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    }
                } else if trimmed.hasPrefix("service_tier =") {
                    let parts = trimmed.split(separator: "=")
                    if parts.count >= 2 {
                        serviceTier = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    }
                }
            }
        }

        let authPath = "\(codexDir)/auth.json"
        if let authData = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
           let authJSON = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] {
            if authJSON["OPENAI_API_KEY"] != nil || authJSON["tokens"] != nil {
                hasApiKey = true
            }
        }

        let status = hasApiKey ? "Đã liên kết OpenAI API (\(serviceTier))" : "Chế độ Local CLI"

        return AIProviderMetrics(
            id: "openai_codex",
            name: "OpenAI / Codex",
            providerType: .openaiCodex,
            iconName: "cpu",
            isDetected: true,
            statusMessage: status,
            activeModel: detectedModel,
            userAccount: hasApiKey ? "OpenAI API Key (Tự động nhận diện)" : nil,
            inputTokensToday: 0,
            outputTokensToday: 0,
            cacheTokensToday: 0,
            totalTokensToday: 0,
            turnsOrPromptsToday: 0,
            activeSessionsToday: 0
        )
    }

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
                statusMessage: "Chưa cấu hình (~/.commandcode)"
            )
        }

        var userName = "User"
        var keyName = "Default"

        let authPath = "\(ccDir)/auth.json"
        if let authData = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
           let authJSON = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] {
            userName = authJSON["userName"] as? String ?? userName
            keyName = authJSON["keyName"] as? String ?? keyName
        }

        var activeProjectsCount = 0
        let projectsDir = "\(ccDir)/projects"
        if let subdirs = try? fm.contentsOfDirectory(atPath: projectsDir) {
            activeProjectsCount = subdirs.count
        }

        return AIProviderMetrics(
            id: "commandcode",
            name: "CommandCode AI",
            providerType: .commandcode,
            iconName: "terminal.fill",
            isDetected: true,
            statusMessage: "Tài khoản: @\(userName) (\(keyName))",
            activeModel: "Claude 3.7 / Inkling",
            userAccount: "@\(userName)",
            inputTokensToday: 0,
            outputTokensToday: 0,
            cacheTokensToday: 0,
            totalTokensToday: 0,
            turnsOrPromptsToday: 0,
            activeSessionsToday: activeProjectsCount
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

        var version = "2.1"
        var userId = "Connected"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: claudePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            version = json["firstStartVersion"] as? String ?? version
            if let uid = json["userID"] as? String {
                userId = String(uid.prefix(8)) + "..."
            }
        }

        return AIProviderMetrics(
            id: "claude",
            name: "Claude Code",
            providerType: .claude,
            iconName: "sparkles",
            isDetected: true,
            statusMessage: "Đã cài đặt v\(version) (ID: \(userId))",
            activeModel: "Claude 3.5 Sonnet / Opus",
            userAccount: "Anthropic Claude"
        )
    }
}
