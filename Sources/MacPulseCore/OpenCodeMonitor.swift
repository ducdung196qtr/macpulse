import Foundation
import Darwin
import SQLite3

public enum OpenCodeTaskOutcome: String, Codable, Sendable, Equatable {
    case succeeded
    case failed
    case interrupted
    case unknown

    public init(rawDatabaseValue: String) {
        switch rawDatabaseValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "succeeded", "success", "completed":
            self = .succeeded
        case "failed", "error":
            self = .failed
        case "interrupted", "cancelled", "canceled", "aborted":
            self = .interrupted
        default:
            self = .unknown
        }
    }

    public var displayLabel: String {
        switch self {
        case .succeeded: return "Hoàn tất"
        case .failed: return "Gặp lỗi"
        case .interrupted: return "Đã dừng"
        case .unknown: return "Đã xong"
        }
    }
}

public struct OpenCodeSessionItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let rawTitle: String
    public let directory: String
    public let parentID: String?
    public let agent: String?
    public let model: String?
    public let latestPrompt: String?
    public let timeBusyMs: Int64?
    public let timeIdleMs: Int64?
    public let timeViewedMs: Int64?
    public let timeUpdatedMs: Int64
    public let outcome: OpenCodeTaskOutcome

    public init(
        id: String,
        rawTitle: String,
        directory: String,
        parentID: String? = nil,
        agent: String? = nil,
        model: String? = nil,
        latestPrompt: String? = nil,
        timeBusyMs: Int64? = nil,
        timeIdleMs: Int64? = nil,
        timeViewedMs: Int64? = nil,
        timeUpdatedMs: Int64,
        outcome: OpenCodeTaskOutcome = .unknown
    ) {
        self.id = id
        self.rawTitle = rawTitle
        self.directory = directory
        self.parentID = parentID
        self.agent = agent
        self.model = model
        self.latestPrompt = latestPrompt
        self.timeBusyMs = timeBusyMs
        self.timeIdleMs = timeIdleMs
        self.timeViewedMs = timeViewedMs
        self.timeUpdatedMs = timeUpdatedMs
        self.outcome = outcome
    }

    public var projectName: String {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" { return "OpenCode" }
        let last = URL(fileURLWithPath: trimmed).lastPathComponent
        return last.isEmpty ? "OpenCode" : last
    }

    public var displayTitle: String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let prompt = cleanedLatestPrompt, !prompt.isEmpty { return prompt }
        return "Phiên làm việc (\(projectName))"
    }

    public var cleanedLatestPrompt: String? {
        guard let raw = latestPrompt else { return nil }
        let singleLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return nil }
        // Hide noisy OpenMausBot injected context prefixes if ever shown
        if singleLine.hasPrefix("Context from OpenMausBot") { return nil }
        if singleLine.count > 90 {
            return String(singleLine.prefix(87)) + "..."
        }
        return singleLine
    }

    /// Cleanly parses OpenCode's JSON model column (`{"id":"gpt-6.1-terra","providerID":"openai"}`) into `"gpt-6.1-terra"`.
    public var displayModel: String? {
        guard let raw = model?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("{"), let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = obj["id"] as? String, !id.isEmpty {
            return id
        }
        return raw
    }

    public var modeBadgeLabel: String? {
        guard let a = agent?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !a.isEmpty else {
            return nil
        }
        switch a {
        case "plan": return "PLAN"
        case "build": return "CODE"
        default: return a.uppercased()
        }
    }

    public var isSubagentSession: Bool {
        if let p = parentID, !p.isEmpty { return true }
        if let a = agent?.lowercased(), a == "explore" || a == "subagent" { return true }
        return false
    }

    public var isBackgroundBotHelper: Bool {
        let lowerDir = directory.lowercased()
        let emptyTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if lowerDir.contains("omb-acp-memory") || lowerDir.contains("/var/folders/") { return true }
        if lowerDir == "/" || lowerDir.isEmpty { return true }
        if emptyTitle && timeViewedMs == nil { return true }
        return false
    }

    /// True ONLY for interactive OpenCode TUI sessions opened by the user (excludes headless OpenMausBot / ACP bot sessions).
    /// In OpenCode's `session_v2`, user TUI sessions always carry `time_viewed` and/or `agent IN ('build', 'plan')`,
    /// whereas headless OpenMausBot/ACP sessions have both `time_viewed IS NULL` and `agent IS NULL`.
    public var isInteractiveUserSession: Bool {
        guard !isSubagentSession && !isBackgroundBotHelper else { return false }
        if let viewed = timeViewedMs, viewed > 0 { return true }
        if let a = agent?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           (a == "build" || a == "plan") {
            return true
        }
        return false
    }

    public func isRunning(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
        guard let busy = timeBusyMs, busy > 0 else { return false }
        let staleCutoffMs: Int64 = 2 * 3600 * 1000 // ignore dead crashed sessions older than 2 hours
        guard nowMs - timeUpdatedMs < staleCutoffMs else { return false }
        if let idle = timeIdleMs, idle >= busy {
            return false
        }
        return true
    }

    public func durationSeconds(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Double {
        guard let busy = timeBusyMs, busy > 0 else { return 0 }
        if isRunning(nowMs: nowMs) {
            return max(0, Double(nowMs - busy) / 1000.0)
        }
        if let idle = timeIdleMs, idle >= busy {
            return max(0, Double(idle - busy) / 1000.0)
        }
        return 0
    }

    public var lastActivityDate: Date {
        let ms = max(timeIdleMs ?? 0, max(timeBusyMs ?? 0, timeUpdatedMs))
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }
}

public struct OpenCodeNotifyConfig: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var playSound: Bool
    public var soundName: String
    public var showFloatingBanner: Bool
    public var showSystemNotification: Bool
    public var onlyInteractiveSessions: Bool
    public var onlyTopLevelSessions: Bool
    public var ignoreEmptyBotSessions: Bool
    public var minDurationSeconds: Int

    public static let availableSounds: [String] = [
        "Glass", "Hero", "Ping", "Submarine", "Pop", "Tink", "Funk"
    ]

    public init(
        isEnabled: Bool = true,
        playSound: Bool = true,
        soundName: String = "Glass",
        showFloatingBanner: Bool = true,
        showSystemNotification: Bool = false,
        onlyInteractiveSessions: Bool = true,
        onlyTopLevelSessions: Bool = true,
        ignoreEmptyBotSessions: Bool = true,
        minDurationSeconds: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.playSound = playSound
        self.soundName = soundName
        self.showFloatingBanner = showFloatingBanner
        self.showSystemNotification = showSystemNotification
        self.onlyInteractiveSessions = onlyInteractiveSessions
        self.onlyTopLevelSessions = onlyTopLevelSessions
        self.ignoreEmptyBotSessions = ignoreEmptyBotSessions
        self.minDurationSeconds = minDurationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, playSound, soundName, showFloatingBanner, showSystemNotification
        case onlyInteractiveSessions, onlyTopLevelSessions, ignoreEmptyBotSessions, minDurationSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.playSound = try c.decodeIfPresent(Bool.self, forKey: .playSound) ?? true
        self.soundName = try c.decodeIfPresent(String.self, forKey: .soundName) ?? "Glass"
        self.showFloatingBanner = try c.decodeIfPresent(Bool.self, forKey: .showFloatingBanner) ?? true
        self.showSystemNotification = try c.decodeIfPresent(Bool.self, forKey: .showSystemNotification) ?? false
        self.onlyInteractiveSessions = try c.decodeIfPresent(Bool.self, forKey: .onlyInteractiveSessions) ?? true
        self.onlyTopLevelSessions = try c.decodeIfPresent(Bool.self, forKey: .onlyTopLevelSessions) ?? true
        self.ignoreEmptyBotSessions = try c.decodeIfPresent(Bool.self, forKey: .ignoreEmptyBotSessions) ?? true
        self.minDurationSeconds = try c.decodeIfPresent(Int.self, forKey: .minDurationSeconds) ?? 0
    }
}

public struct OpenCodeCompletionEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let sessionID: String
    public let title: String
    public let promptSummary: String?
    public let modeLabel: String?
    public let projectName: String
    public let directory: String
    public let outcome: OpenCodeTaskOutcome
    public let durationSeconds: Double
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: String,
        title: String,
        promptSummary: String? = nil,
        modeLabel: String? = nil,
        projectName: String,
        directory: String,
        outcome: OpenCodeTaskOutcome,
        durationSeconds: Double,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.promptSummary = promptSummary
        self.modeLabel = modeLabel
        self.projectName = projectName
        self.directory = directory
        self.outcome = outcome
        self.durationSeconds = durationSeconds
        self.completedAt = completedAt
    }
}

public struct PersistedOpenCodeNotifyState: Codable, Sendable, Equatable {
    public var config: OpenCodeNotifyConfig
    public var recentAlerts: [OpenCodeCompletionEvent]

    public init(
        config: OpenCodeNotifyConfig = OpenCodeNotifyConfig(),
        recentAlerts: [OpenCodeCompletionEvent] = []
    ) {
        self.config = config
        self.recentAlerts = recentAlerts
    }
}

public final class OpenCodeMonitorStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            self.fileURL = appSupport
                .appendingPathComponent("MacPulse", isDirectory: true)
                .appendingPathComponent("opencode-notify.json")
        }
    }

    public func load() -> PersistedOpenCodeNotifyState {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PersistedOpenCodeNotifyState.self, from: data) else {
            return PersistedOpenCodeNotifyState()
        }
        return decoded
    }

    public func save(_ state: PersistedOpenCodeNotifyState) throws {
        lock.lock()
        defer { lock.unlock() }
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

public struct OpenCodePollResult: Sendable, Equatable {
    public let isDatabaseAvailable: Bool
    public let runningSessions: [OpenCodeSessionItem]
    public let recentSessions: [OpenCodeSessionItem]
    public let newlyCompleted: [OpenCodeCompletionEvent]
    public let didReadDatabase: Bool

    public init(
        isDatabaseAvailable: Bool,
        runningSessions: [OpenCodeSessionItem],
        recentSessions: [OpenCodeSessionItem],
        newlyCompleted: [OpenCodeCompletionEvent],
        didReadDatabase: Bool
    ) {
        self.isDatabaseAvailable = isDatabaseAvailable
        self.runningSessions = runningSessions
        self.recentSessions = recentSessions
        self.newlyCompleted = newlyCompleted
        self.didReadDatabase = didReadDatabase
    }
}

/// High-efficiency OpenCode session watcher.
/// Uses a zero-I/O `stat()` check on `opencode.db` + `opencode.db-wal` before ever opening SQLite,
/// and accurately isolates interactive user TUI sessions from background OpenMausBot/ACP bots.
public final class OpenCodeMonitor: @unchecked Sendable {
    private struct FileFingerprint: Equatable {
        let dbMtimeSec: Int
        let dbMtimeNsec: Int
        let dbSize: Int64
        let walMtimeSec: Int
        let walMtimeNsec: Int
        let walSize: Int64
    }

    public let databaseURL: URL
    private let lock = NSLock()
    private var lastFingerprint: FileFingerprint?
    private var isInitialized = false
    private var baselineTimestampMs: Int64 = 0
    private var knownIdleMsBySession: [String: Int64] = [:]
    private var observedBusySessions: Set<String> = []
    private var cachedRunning: [OpenCodeSessionItem] = []
    private var cachedRecent: [OpenCodeSessionItem] = []

    public init(databaseURL: URL? = nil) {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.databaseURL = home
                .appendingPathComponent(".local/share/opencode/opencode.db")
        }
    }

    public static func formatDuration(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            let h = total / 3600
            let m = (total % 3600) / 60
            return "\(h)h \(String(format: "%02d", m))m"
        } else if total >= 60 {
            let m = total / 60
            let s = total % 60
            return "\(m)m \(String(format: "%02d", s))s"
        } else {
            return "\(total)s"
        }
    }

    private func currentFingerprint() -> FileFingerprint? {
        var dbStat = stat()
        guard stat(databaseURL.path, &dbStat) == 0 else { return nil }
        var walStat = stat()
        let walPath = databaseURL.path + "-wal"
        let hasWal = (stat(walPath, &walStat) == 0)
        return FileFingerprint(
            dbMtimeSec: dbStat.st_mtimespec.tv_sec,
            dbMtimeNsec: dbStat.st_mtimespec.tv_nsec,
            dbSize: dbStat.st_size,
            walMtimeSec: hasWal ? walStat.st_mtimespec.tv_sec : 0,
            walMtimeNsec: hasWal ? walStat.st_mtimespec.tv_nsec : 0,
            walSize: hasWal ? walStat.st_size : 0
        )
    }

    /// Polls OpenCode state. Returns immediately without opening SQLite if DB/WAL files haven't changed.
    public func poll(
        config: OpenCodeNotifyConfig,
        forceRead: Bool = false,
        now: Date = Date()
    ) -> OpenCodePollResult {
        guard let fp = currentFingerprint() else {
            return OpenCodePollResult(
                isDatabaseAvailable: false,
                runningSessions: [],
                recentSessions: [],
                newlyCompleted: [],
                didReadDatabase: false
            )
        }

        lock.lock()
        if !forceRead && isInitialized && lastFingerprint == fp {
            let r = cachedRunning
            let rec = cachedRecent
            lock.unlock()
            return OpenCodePollResult(
                isDatabaseAvailable: true,
                runningSessions: r,
                recentSessions: rec,
                newlyCompleted: [],
                didReadDatabase: false
            )
        }
        lock.unlock()

        let sessions = Self.queryRecentSessions(
            dbPath: databaseURL.path,
            onlyInteractive: config.onlyInteractiveSessions,
            limit: 40
        )
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        lock.lock()
        defer { lock.unlock() }

        lastFingerprint = fp
        return processSessionsLocked(sessions: sessions, config: config, nowMs: nowMs)
    }

    /// Pure state-transition evaluator (exposed for deterministic unit testing without SQLite files).
    public func evaluateSnapshotForTesting(
        sessions: [OpenCodeSessionItem],
        config: OpenCodeNotifyConfig,
        now: Date = Date()
    ) -> OpenCodePollResult {
        lock.lock()
        defer { lock.unlock() }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        return processSessionsLocked(sessions: sessions, config: config, nowMs: nowMs)
    }

    private func processSessionsLocked(
        sessions: [OpenCodeSessionItem],
        config: OpenCodeNotifyConfig,
        nowMs: Int64
    ) -> OpenCodePollResult {
        let filtered = sessions.filter { item in
            if config.onlyInteractiveSessions && !item.isInteractiveUserSession { return false }
            if config.onlyTopLevelSessions && item.isSubagentSession { return false }
            if config.ignoreEmptyBotSessions && item.isBackgroundBotHelper { return false }
            return true
        }

        let running = filtered.filter { $0.isRunning(nowMs: nowMs) }
        let recent = Array(filtered.prefix(12))

        if !isInitialized {
            isInitialized = true
            baselineTimestampMs = nowMs
            for s in sessions {
                if let idle = s.timeIdleMs {
                    knownIdleMsBySession[s.id] = idle
                }
                if s.isRunning(nowMs: nowMs) {
                    observedBusySessions.insert(s.id)
                }
            }
            cachedRunning = running
            cachedRecent = recent
            return OpenCodePollResult(
                isDatabaseAvailable: true,
                runningSessions: running,
                recentSessions: recent,
                newlyCompleted: [],
                didReadDatabase: true
            )
        }

        var newlyCompleted: [OpenCodeCompletionEvent] = []

        for s in filtered {
            if s.isRunning(nowMs: nowMs) {
                observedBusySessions.insert(s.id)
                continue
            }

            if let idleMs = s.timeIdleMs, idleMs > 0 {
                let busyMs = s.timeBusyMs ?? 0
                let prevIdle = knownIdleMsBySession[s.id] ?? 0
                let wasObservedBusy = observedBusySessions.contains(s.id)
                let threshold = max(prevIdle, baselineTimestampMs)

                if idleMs >= busyMs && idleMs > threshold {
                    let duration = busyMs > 0 ? Double(max(0, idleMs - busyMs)) / 1000.0 : 0
                    let meetsDuration = duration >= Double(max(0, config.minDurationSeconds))
                    if config.isEnabled && (meetsDuration || (wasObservedBusy && s.outcome == .failed)) {
                        newlyCompleted.append(OpenCodeCompletionEvent(
                            sessionID: s.id,
                            title: s.displayTitle,
                            promptSummary: s.cleanedLatestPrompt,
                            modeLabel: s.modeBadgeLabel,
                            projectName: s.projectName,
                            directory: s.directory,
                            outcome: s.outcome,
                            durationSeconds: duration,
                            completedAt: Date(timeIntervalSince1970: Double(idleMs) / 1000.0)
                        ))
                    }
                }
                if idleMs > prevIdle {
                    knownIdleMsBySession[s.id] = idleMs
                }
                observedBusySessions.remove(s.id)
            }
        }

        if knownIdleMsBySession.count > 128 {
            let activeIDs = Set(sessions.map(\.id))
            knownIdleMsBySession = knownIdleMsBySession.filter { activeIDs.contains($0.key) }
        }

        cachedRunning = running
        cachedRecent = recent

        return OpenCodePollResult(
            isDatabaseAvailable: true,
            runningSessions: running,
            recentSessions: recent,
            newlyCompleted: newlyCompleted,
            didReadDatabase: true
        )
    }

    public static func queryRecentSessions(
        dbPath: String,
        onlyInteractive: Bool = true,
        limit: Int = 40
    ) -> [OpenCodeSessionItem] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)

        let whereClause = onlyInteractive
            ? "WHERE parent_id IS NULL AND (time_viewed IS NOT NULL OR agent IN ('build', 'plan'))"
            : ""

        let sql = """
        SELECT id, coalesce(title, ''), coalesce(directory, ''), parent_id, agent, model,
               time_busy, time_idle, time_viewed, coalesce(idle_outcome, ''), time_updated
        FROM session_v2
        \(whereClause)
        ORDER BY time_updated DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        struct RawRow {
            let id: String
            let rawTitle: String
            let directory: String
            let parentID: String?
            let agent: String?
            let model: String?
            let timeBusyMs: Int64?
            let timeIdleMs: Int64?
            let timeViewedMs: Int64?
            let outcomeRaw: String
            let timeUpdatedMs: Int64
        }

        var rows: [RawRow] = []
        rows.reserveCapacity(limit)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0)
            guard !id.isEmpty else { continue }
            rows.append(RawRow(
                id: id,
                rawTitle: columnText(stmt, 1),
                directory: columnText(stmt, 2),
                parentID: columnOptionalText(stmt, 3),
                agent: columnOptionalText(stmt, 4),
                model: columnOptionalText(stmt, 5),
                timeBusyMs: columnOptionalInt64(stmt, 6),
                timeIdleMs: columnOptionalInt64(stmt, 7),
                timeViewedMs: columnOptionalInt64(stmt, 8),
                outcomeRaw: columnText(stmt, 9),
                timeUpdatedMs: sqlite3_column_int64(stmt, 10)
            ))
        }

        // Enrich top 8 sessions with latest user prompt & latest active agent mode via indexed lookup (~0.1ms each)
        var promptStmt: OpaquePointer?
        let hasPromptTable = sqlite3_prepare_v2(
            db,
            "SELECT substr(data, 1, 512) FROM session_message WHERE session_id = ? AND type = 'user' ORDER BY seq DESC LIMIT 1;",
            -1,
            &promptStmt,
            nil
        ) == SQLITE_OK
        defer { if let promptStmt { sqlite3_finalize(promptStmt) } }

        var agentStmt: OpaquePointer?
        let hasAgentTable = sqlite3_prepare_v2(
            db,
            "SELECT substr(data, 1, 256) FROM session_message WHERE session_id = ? AND type = 'assistant' ORDER BY seq DESC LIMIT 1;",
            -1,
            &agentStmt,
            nil
        ) == SQLITE_OK
        defer { if let agentStmt { sqlite3_finalize(agentStmt) } }

        var items: [OpenCodeSessionItem] = []
        items.reserveCapacity(rows.count)

        for (idx, row) in rows.enumerated() {
            var latestPrompt: String? = nil
            var effectiveAgent = row.agent

            if idx < 8 {
                if hasPromptTable, let ps = promptStmt {
                    sqlite3_reset(ps)
                    sqlite3_clear_bindings(ps)
                    sqlite3_bind_text(ps, 1, (row.id as NSString).utf8String, -1, nil)
                    if sqlite3_step(ps) == SQLITE_ROW {
                        let rawJSON = columnText(ps, 0)
                        latestPrompt = extractJSONStringField(from: rawJSON, key: "text")
                    }
                }
                if hasAgentTable, let ast = agentStmt {
                    sqlite3_reset(ast)
                    sqlite3_clear_bindings(ast)
                    sqlite3_bind_text(ast, 1, (row.id as NSString).utf8String, -1, nil)
                    if sqlite3_step(ast) == SQLITE_ROW {
                        let rawJSON = columnText(ast, 0)
                        if let liveAgent = extractJSONStringField(from: rawJSON, key: "agent"), !liveAgent.isEmpty {
                            effectiveAgent = liveAgent
                        }
                    }
                }
            }

            items.append(OpenCodeSessionItem(
                id: row.id,
                rawTitle: row.rawTitle,
                directory: row.directory,
                parentID: row.parentID,
                agent: effectiveAgent,
                model: row.model,
                latestPrompt: latestPrompt,
                timeBusyMs: row.timeBusyMs,
                timeIdleMs: row.timeIdleMs,
                timeViewedMs: row.timeViewedMs,
                timeUpdatedMs: row.timeUpdatedMs,
                outcome: OpenCodeTaskOutcome(rawDatabaseValue: row.outcomeRaw)
            ))
        }

        return items
    }

    private static func extractJSONStringField(from raw: String, key: String) -> String? {
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let val = obj[key] as? String {
            return val
        }
        // Fast fallback for truncated JSON prefix (substr(data, 1, 512))
        let needle = "\"\(key)\":\""
        guard let range = raw.range(of: needle) else { return nil }
        var out = ""
        var escaped = false
        for ch in raw[range.upperBound...] {
            if escaped {
                switch ch {
                case "n": out.append(" ")
                case "t": out.append(" ")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default: out.append(ch)
                }
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == "\"" { break }
            out.append(ch)
            if out.count >= 120 { break }
        }
        return out.isEmpty ? nil : out
    }

    private static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private static func columnOptionalText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let s = String(cString: ptr)
        return s.isEmpty ? nil : s
    }

    private static func columnOptionalInt64(_ stmt: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, index)
    }
}
