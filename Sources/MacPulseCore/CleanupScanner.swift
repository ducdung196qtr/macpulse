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
        let cacheSpecs: [(id: String, title: String, subtitle: String, relPaths: [String], defaultChecked: Bool)] = [
            ("cache-chrome", "Cache Google Chrome (Web, GPU/Shader & Service Worker)", "Xoá cache web, GPU/Shader & CacheStorage mọi Profile; giữ nguyên tài khoản, mật khẩu, bookmark & tab.", chromePaths, true),
            ("cache-edge", "Cache Microsoft Edge", "Chỉ xoá file đệm tạm của Edge; giữ nguyên đăng nhập.", ["Library/Caches/Microsoft Edge"], true),
            ("cache-safari", "Cache Safari", "Chỉ xoá file đệm trình duyệt Safari; không mất bookmark/lịch sử.", ["Library/Caches/com.apple.Safari"], true),
            ("cache-npm", "Cache npm (_cacache)", "Gói tải tạm của npm — tự tải lại nếu chạy npm install.", [".npm/_cacache"], true),
            ("cache-uv-pip", "Cache Python uv / pip", "Gói tải tạm của uv và pip.", [".cache/uv", ".cache/pip", "Library/Caches/pip"], true),
            ("cache-yarn-pnpm", "Cache Yarn / pnpm", "Gói tải tạm của Yarn / pnpm.", ["Library/Caches/Yarn", ".cache/yarn", "Library/pnpm/store"], false),
            ("cache-swiftpm", "Cache Swift Package Manager", "Cache source/manifest của SwiftPM; Xcode/Swift tự tải lại khi build.", ["Library/Caches/org.swift.swiftpm"], true),
            ("cache-hf", "Cache HuggingFace (~/.cache/huggingface)", "Model AI cache tải về — chỉ tick nếu không còn chạy model AI offline.", [".cache/huggingface"], false),
        ]

        for spec in cacheSpecs {
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
                    category: .cache
                ))
            }
        }

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
            ("inspect-xcode-derived", "Xcode DerivedData", "Dữ liệu build trung gian của Xcode/Swift trên SSD — mở Finder kiểm tra nếu không cần giữ cache build.", "Library/Developer/Xcode/DerivedData"),
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


    public static func chromeCacheRelativePaths(homeDirectory: URL) -> [String] {
        var rels: [String] = [
            "Library/Caches/Google/Chrome",
            "Library/Application Support/Google/Chrome/GrShaderCache",
            "Library/Application Support/Google/Chrome/GraphiteDawnCache",
            "Library/Application Support/Google/Chrome/GPUPersistentCache",
            "Library/Application Support/Google/Chrome/ShaderCache"
        ]
        let appSupportChrome = homeDirectory.appendingPathComponent("Library/Application Support/Google/Chrome")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: appSupportChrome,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let profileCacheSubdirs = [
                "Cache",
                "Code Cache",
                "GPUCache",
                "DawnGraphiteCache",
                "DawnWebGPUCache",
                "Service Worker/CacheStorage",
                "Service Worker/ScriptCache"
            ]
            for entry in entries {
                let name = entry.lastPathComponent
                let isProfile = name == "Default"
                    || name == "Guest Profile"
                    || name == "System Profile"
                    || name.hasPrefix("Profile ")
                guard isProfile else { continue }
                for sub in profileCacheSubdirs {
                    rels.append("Library/Application Support/Google/Chrome/\(name)/\(sub)")
                }
            }
        }
        return rels
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
