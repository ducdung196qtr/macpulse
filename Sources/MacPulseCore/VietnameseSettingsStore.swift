import Foundation

public struct PersistedVietnameseConfig: Codable, Equatable, Sendable {
    public var settings: VietnameseSettings
    public var perAppEnabled: [String: Bool]

    public init(settings: VietnameseSettings = VietnameseSettings(), perAppEnabled: [String: Bool] = [:]) {
        self.settings = settings
        self.perAppEnabled = perAppEnabled
    }
}

public final class VietnameseSettingsStore {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            self.fileURL = appSupport
                .appendingPathComponent("MacPulse", isDirectory: true)
                .appendingPathComponent("ime-settings.json")
        }
    }

    public func load() -> PersistedVietnameseConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PersistedVietnameseConfig.self, from: data) else {
            return PersistedVietnameseConfig()
        }
        return decoded
    }

    public func save(_ config: PersistedVietnameseConfig) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    public var storagePath: String { fileURL.path }
}
