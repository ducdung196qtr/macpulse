import Foundation

public final class CleanupScanner {
    public let homeDirectory: URL
    public let oversizedLogThresholdBytes: UInt64
    public let inspectThresholdBytes: UInt64

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        oversizedLogThresholdBytes: UInt64 = 10 * 1_048_576,
        inspectThresholdBytes: UInt64 = 500 * 1_048_576
    ) {
        self.homeDirectory = homeDirectory
        self.oversizedLogThresholdBytes = oversizedLogThresholdBytes
        self.inspectThresholdBytes = inspectThresholdBytes
    }

    public func scan() -> [CleanupCandidate] {
        var results: [CleanupCandidate] = []

        let chromePaths = Self.chromeCacheRelativePaths(homeDirectory: homeDirectory)

        // 1. Rác do AI tạo ra (Cursor, Codex, Claude, Gemini, AI Models)
        let aiSpecs: [(id: String, title: String, subtitle: String, relPaths: [String], defaultChecked: Bool)] = [
            (
                "cache-cursor-ai",
                "Cache & Logs Cursor AI",
                "Tệp đệm biên dịch, GPU Cache, logs và telemetry tạm thời của Cursor (không mất settings/extension).",
                [
                    "Library/Application Support/Cursor/CachedData",
                    "Library/Application Support/Cursor/CachedExtensionVSIXs",
                    "Library/Application Support/Cursor/GPUCache",
                    "Library/Application Support/Cursor/logs",
                    "Library/Caches/cursor-compile-cache",
                    ".cursor/ai-tracking"
                ],
                true
            ),
            (
                "cache-codex-ai",
                "Cache & Tệp tạm Codex AI",
                "Bộ đệm phiên làm việc, tệp tmp và cache dịch vụ Computer Use của Codex (không làm mất prompt/key).",
                [
                    ".codex/cache",
                    ".codex/tmp",
                    "Library/Caches/Codex",
                    "Library/Caches/com.openai.codex",
                    "Library/Caches/com.openai.sky.CUAService"
                ],
                true
            ),
            (
                "cache-claude-ai",
                "Cache & Logs Claude AI",
                "Bộ đệm cache phản hồi, log và ShipIt của Claude Desktop & Claude Code.",
                [
                    ".claude/cache",
                    ".claude/logs",
                    "Library/Caches/com.anthropic.claudedesktop",
                    "Library/Caches/com.anthropic.claudedesktop.ShipIt"
                ],
                true
            ),
            (
                "cache-gemini-ai",
                "Cache & Bản cập nhật Antigravity / Gemini",
                "Cache cập nhật ShipIt, bộ đệm ứng dụng Antigravity, log phiên và sandbox npm tạm (không mất lịch sử chat hay settings).",
                [
                    "Library/Caches/com.google.antigravity.ShipIt",
                    "Library/Caches/com.google.antigravity",
                    ".gemini/logs",
                    ".cache/opencode-antigravity-npm",
                    ".cache/opencode"
                ],
                true
            ),
            (
                "cache-openmausbot-ai",
                "Cache & Bản cập nhật OpenMausBot",
                "File cập nhật tải về và bộ đệm GPU/Shader/Web tạm của profile bot (giữ nguyên 100% đăng nhập, cookie và lịch sử bot).",
                Self.openMausBotSafeCacheRelativePaths(homeDirectory: homeDirectory),
                true
            ),
            (
                "cache-ai-models",
                "Mô hình AI tải về & PyTorch Cache",
                "Cache tải mô hình HuggingFace, Whisper, PyTorch kernels tải về ổ cứng (chỉ tick khi muốn giải phóng ổ cứng).",
                [
                    ".cache/huggingface",
                    ".cache/whisper",
                    ".cache/torch"
                ],
                false
            )
        ]

        // 2. Cache Trình duyệt Web
        let browserSpecs: [(id: String, title: String, subtitle: String, relPaths: [String], defaultChecked: Bool)] = [
            ("cache-chrome", "Cache Web Google Chrome", "Chỉ xoá bộ đệm web tạm (~/Library/Caches). 100% an toàn: bảo vệ tuyệt đối Extension, Service Worker, tab và tài khoản.", chromePaths, true),
            ("cache-brave", "Cache Brave Browser", "Chỉ xoá file đệm web tạm của Brave; giữ nguyên 100% Extension, tab và mật khẩu.", ["Library/Caches/BraveSoftware"], true),
            ("cache-edge", "Cache Microsoft Edge", "Chỉ xoá file đệm tạm của Edge; giữ nguyên đăng nhập.", ["Library/Caches/Microsoft Edge"], true),
            ("cache-safari", "Cache Safari", "Chỉ xoá file đệm trình duyệt Safari; không mất bookmark/lịch sử.", ["Library/Caches/com.apple.Safari"], true),
            ("cache-arc", "Cache Arc Browser", "Xoá file đệm web & shader của Arc Browser; giữ nguyên tab và Space.", ["Library/Caches/company.thebrowser.Browser"], true),
            ("cache-firefox", "Cache Mozilla Firefox", "Xoá file đệm web tạm của Firefox; giữ nguyên add-on và tài khoản.", ["Library/Caches/Firefox"], true)
        ]

        // 3. Cache Lập trình & Build
        let devSpecs: [(id: String, title: String, subtitle: String, relPaths: [String], defaultChecked: Bool)] = [
            ("cache-vscode", "Cache Visual Studio Code", "Cache đệm tạm và ShipIt của VS Code; không ảnh hưởng settings/extension.", ["Library/Caches/com.microsoft.VSCode", "Library/Caches/com.microsoft.VSCode.ShipIt"], true),
            ("cache-homebrew", "Cache Homebrew Cask & Downloads", "Tệp nén .bottle và installer đã tải về của brew; brew tự tải lại khi cần.", ["Library/Caches/Homebrew"], true),
            ("cache-npm", "Cache npm (_cacache)", "Gói tải tạm của npm — tự tải lại nếu chạy npm install.", [".npm/_cacache"], true),
            ("cache-uv-pip", "Cache Python uv / pip", "Gói tải tạm của uv và pip.", [".cache/uv", ".cache/pip", "Library/Caches/pip"], true),
            ("cache-composer", "Cache PHP Composer", "Gói tải tạm của Composer; tự tải lại khi chạy composer install.", ["Library/Caches/composer"], true),
            ("cache-swiftpm", "Cache Swift Package Manager", "Cache source/manifest của SwiftPM; Xcode/Swift tự tải lại khi build.", ["Library/Caches/org.swift.swiftpm"], true),
            ("cache-xcode-derived", "Xcode DerivedData (Build trung gian)", "Xoá tệp build tạm của Xcode/Swift để giải phóng ổ cứng (Xcode tự build lại khi nhấn Run).", ["Library/Developer/Xcode/DerivedData"], false),
            ("cache-yarn-pnpm", "Cache Yarn / pnpm", "Gói tải tạm của Yarn / pnpm.", ["Library/Caches/Yarn", ".cache/yarn", "Library/pnpm/store"], false),
            ("cache-cocoapods", "Cache CocoaPods", "Cache repository và package của CocoaPods.", ["Library/Caches/CocoaPods"], false),
            ("cache-gradle", "Cache Gradle (~/.gradle/caches)", "Cache dependency của Gradle / Android Studio.", [".gradle/caches"], false),
            ("cache-docker", "Cache Docker Desktop", "Bộ đệm tạm của Docker Desktop.", ["Library/Caches/com.docker.docker"], false)
        ]

        // 4. File rác hệ thống
        let systemSpecs: [(id: String, title: String, subtitle: String, relPaths: [String], defaultChecked: Bool)] = [
            ("cache-quicklook", "Cache QuickLook Thumbnail", "Bộ đệm hình xem nhanh QuickLook của Finder.", ["Library/Caches/com.apple.QuickLook.thumbnailcache"], true)
        ]

        func scanGroup(
            specs: [(id: String, title: String, subtitle: String, relPaths: [String], defaultChecked: Bool)],
            category: CleanupCategory
        ) {
            for spec in specs {
                var total: UInt64 = 0
                var existingPaths: [String] = []
                for rel in spec.relPaths {
                    let url = homeDirectory.appendingPathComponent(rel)
                    if FileManager.default.fileExists(atPath: url.path) {
                        let sz = Self.directorySize(at: url)
                        if sz > 0 {
                            total += sz
                            existingPaths.append(url.path)
                        }
                    }
                }
                if total >= 64 * 1024, let primary = existingPaths.first {
                    results.append(CleanupCandidate(
                        id: spec.id,
                        title: spec.title,
                        subtitle: spec.subtitle,
                        path: existingPaths.joined(separator: "|"),
                        sizeBytes: total,
                        tier: .safeAutoClean,
                        method: .clearDirectoryContents,
                        defaultSelected: spec.defaultChecked && primary.hasPrefix(homeDirectory.path),
                        category: category
                    ))
                }
            }
        }

        scanGroup(specs: aiSpecs, category: .aiGarbage)
        scanGroup(specs: browserSpecs, category: .cache)
        scanGroup(specs: devSpecs, category: .developerBuild)
        scanGroup(specs: systemSpecs, category: .logsAndTrash)

        let localSitesURL = homeDirectory.appendingPathComponent("Local Sites")
        if let siteDirs = try? FileManager.default.contentsOfDirectory(at: localSitesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for site in siteDirs {
                let logsDir = site.appendingPathComponent("logs")
                guard FileManager.default.fileExists(atPath: logsDir.path) else { continue }
                if let en = FileManager.default.enumerator(at: logsDir, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]) {
                    for case let fileURL as URL in en {
                        guard fileURL.pathExtension.lowercased() == "log" || fileURL.lastPathComponent.contains("error.log") else { continue }
                        let size = Self.fileSize(at: fileURL)
                        if size >= oversizedLogThresholdBytes {
                            results.append(CleanupCandidate(
                                id: "log-\(site.lastPathComponent)-\(fileURL.lastPathComponent)",
                                title: "Log LocalWP: \(site.lastPathComponent)/\(fileURL.lastPathComponent)",
                                subtitle: "Cắt rỗng nội dung file log phình to (giữ file, 0% ảnh hưởng web/DB).",
                                path: fileURL.path,
                                sizeBytes: size,
                                tier: .safeAutoClean,
                                method: .truncateLogFile,
                                defaultSelected: true,
                                category: .logsAndTrash
                            ))
                        }
                    }
                }
            }
        }

        let trashURL = homeDirectory.appendingPathComponent(".Trash")
        let trashSize = Self.directorySize(at: trashURL)
        if trashSize >= 1_048_576 {
            results.append(CleanupCandidate(
                id: "user-trash",
                title: "Thùng rác (~/.Trash)",
                subtitle: "Xoá vĩnh viễn file bạn đã bỏ vào Thùng rác (tắt mặc định để tránh xoá nhầm).",
                path: trashURL.path,
                sizeBytes: trashSize,
                tier: .safeAutoClean,
                method: .emptyTrash,
                defaultSelected: false,
                category: .logsAndTrash
            ))
        }

        let inspectSpecs: [(id: String, title: String, subtitle: String, rel: String)] = [
            ("inspect-opencode-db", "OpenCode Database (opencode.db)", "Dữ liệu lịch sử phiên OpenCode trên ổ cứng — KHÔNG tự xoá. Bấm Mở Finder nếu muốn tự dọn/backup.", ".local/share/opencode/opencode.db"),
            ("inspect-codex-runtimes", "Codex Runtimes (~/.cache/codex-runtimes)", "Bộ chạy nền Codex Desktop trên SSD — chỉ mở Finder xem, xoá sẽ phải tải lại khi mở Codex.", ".cache/codex-runtimes"),
            ("inspect-puppeteer-browsers", "Trình duyệt Puppeteer (~/.cache/puppeteer)", "Bộ Chromium tải sẵn cho automation/MCP — mở Finder xem nếu muốn dọn bản cũ.", ".cache/puppeteer"),
            ("inspect-playwright-browsers", "Trình duyệt Playwright (ms-playwright)", "Các bản Chromium/WebKit tải sẵn cho Playwright — chỉ xem Finder nếu muốn dọn bản cũ.", "Library/Caches/ms-playwright"),
            ("inspect-antigravity-brain", "Dữ liệu phiên Antigravity (~/.gemini/antigravity/brain)", "Lịch sử hội thoại, ảnh chụp & log phiên AI — KHÔNG tự xoá, mở Finder nếu muốn dọn phiên cũ.", ".gemini/antigravity/brain")
        ]

        for spec in inspectSpecs {
            let url = homeDirectory.appendingPathComponent(spec.rel)
            if FileManager.default.fileExists(atPath: url.path) {
                let sz = Self.pathSize(at: url)
                if sz >= inspectThresholdBytes {
                    results.append(CleanupCandidate(
                        id: spec.id,
                        title: spec.title,
                        subtitle: spec.subtitle,
                        path: url.path,
                        sizeBytes: sz,
                        tier: .inspectOnly,
                        method: .inspectInFinderOnly,
                        defaultSelected: false,
                        category: .storageHeavyData
                    ))
                }
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    public static func openMausBotSafeCacheRelativePaths(homeDirectory: URL) -> [String] {
        var paths = ["Library/Caches/openmausbot-updater"]
        let profilesBase = homeDirectory.appendingPathComponent(".openmausbot/agent-browser-profiles")
        let fm = FileManager.default
        if let subs = try? fm.contentsOfDirectory(at: profilesBase, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let safeCacheSubdirs = [
                "Default/Cache",
                "Default/Code Cache",
                "GPUPersistentCache",
                "GraphiteDawnCache",
                "component_crx_cache",
                "extensions_crx_cache"
            ]
            for sub in subs {
                let profileName = sub.lastPathComponent
                for rel in safeCacheSubdirs {
                    paths.append(".openmausbot/agent-browser-profiles/\(profileName)/\(rel)")
                }
            }
        }
        return paths
    }


    public static func chromeCacheRelativePaths(homeDirectory: URL) -> [String] {
        // macOS pure OS cache for Chrome (safely purgeable, never contains extensions, tabs, or user data)
        return [
            "Library/Caches/Google/Chrome"
        ]
    }

    public static func chromeCachePaths(homeDirectory: URL) -> [URL] {
        chromeCacheRelativePaths(homeDirectory: homeDirectory)
            .map { homeDirectory.appendingPathComponent($0) }
    }

    public static func pathSize(at url: URL) -> UInt64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        return isDir.boolValue ? directorySize(at: url) : fileSize(at: url)
    }

    public static func fileSize(at url: URL) -> UInt64 {
        let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return UInt64(max(0, vals?.totalFileAllocatedSize ?? vals?.fileSize ?? 0))
    }

    public static func directorySize(at url: URL) -> UInt64 {
        guard let en = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in en {
            let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            if vals?.isSymbolicLink == true { continue }
            if vals?.isRegularFile == true {
                total += UInt64(max(0, vals?.totalFileAllocatedSize ?? vals?.fileSize ?? 0))
            }
        }
        return total
    }
}
