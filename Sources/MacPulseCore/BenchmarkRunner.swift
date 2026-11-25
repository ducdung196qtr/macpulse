import Foundation
import Darwin

public final class BenchmarkRunner {
    public let historyFileURL: URL
    public let diskTestBytes: Int

    public init(
        historyFileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPulse/benchmarks.json"),
        diskTestBytes: Int = 64 * 1_048_576
    ) {
        self.historyFileURL = historyFileURL
        self.diskTestBytes = diskTestBytes
    }

    public func loadHistory() -> [BenchmarkResult] {
        guard let data = try? Data(contentsOf: historyFileURL),
              let decoded = try? JSONDecoder().decode([BenchmarkResult].self, from: data) else {
            return []
        }
        return decoded
    }

    public func saveResult(_ result: BenchmarkResult) throws {
        let dir = historyFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var history = loadHistory()
        history.insert(result, at: 0)
        if history.count > 30 {
            history = Array(history.prefix(30))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        try data.write(to: historyFileURL, options: .atomic)
    }

    public func clearHistory() throws {
        if FileManager.default.fileExists(atPath: historyFileURL.path) {
            try FileManager.default.removeItem(at: historyFileURL)
        }
    }

    public static func discoverLocalWPSites(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        let localSitesURL = homeDirectory.appendingPathComponent("Local Sites")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: localSitesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    public static func compositeScore(for result: BenchmarkResult) -> Int {
        let singlePart = min(1.0, result.cpuSingleOpsPerSec / 700_000_000.0) * 25.0
        let multiPart = min(1.0, result.cpuMultiOpsPerSec / 3_200_000_000.0) * 25.0
        let memPart = min(1.0, result.memoryBandwidthGBs / 65.0) * 25.0
        let diskAvg = (result.diskWriteMBs + result.diskReadMBs) / 2.0
        let diskPart = min(1.0, diskAvg / 1500.0) * 25.0
        return max(1, min(100, Int((singlePart + multiPart + memPart + diskPart).rounded())))
    }

    public func runSync(localURLToProbe: URL? = nil, onProgress: ((String) -> Void)? = nil) throws -> BenchmarkResult {
        let overallStart = ContinuousClock.now

        onProgress?("Đang đo CPU đơn nhân...")
        let cpuSingle = measureCPUSingle()

        onProgress?("Đang đo CPU đa nhân...")
        let cpuMulti = measureCPUMulti()

        onProgress?("Đang đo băng thông RAM...")
        let memGBs = measureMemoryBandwidth()

        onProgress?("Đang đo tốc độ đọc/ghi SSD...")
        let (writeMBs, readMBs) = try measureDiskIO(totalBytes: diskTestBytes)

        var wpLatency: Double?
        var wpStatus: Int?
        if let url = localURLToProbe {
            onProgress?("Đang đo phản hồi \(url.host ?? "LocalWP")...")
            let probe = probeHTTP(url: url)
            wpLatency = probe.latencyMs
            wpStatus = probe.statusCode
        }

        let elapsed = overallStart.duration(to: .now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        let result = BenchmarkResult(
            cpuSingleOpsPerSec: cpuSingle,
            cpuMultiOpsPerSec: cpuMulti,
            memoryBandwidthGBs: memGBs,
            diskWriteMBs: writeMBs,
            diskReadMBs: readMBs,
            localWPLatencyMs: wpLatency,
            localWPStatusCode: wpStatus,
            totalDurationSeconds: seconds
        )
        try saveResult(result)
        return result
    }

    @inline(never)
    private func cpuKernel(iterations: Int, seed: UInt64) -> UInt64 {
        var acc: UInt64 = 0x9e3779b97f4a7c15 ^ seed
        for i in 1...iterations {
            acc = acc &* 6364136223846793005 &+ UInt64(i)
            acc ^= acc >> 30
            acc = acc &* 0xbf58476d1ce4e5b9
        }
        return acc
    }

    private func elapsedSeconds(since t0: ContinuousClock.Instant) -> Double {
        let elapsed = t0.duration(to: .now)
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private func measureCPUSingle() -> Double {
        let batch = 2_000_000
        var totalOps = 0
        var sink = UInt64(DispatchTime.now().uptimeNanoseconds)
        let t0 = ContinuousClock.now
        repeat {
            sink ^= cpuKernel(iterations: batch, seed: sink)
            totalOps += batch
        } while elapsedSeconds(since: t0) < 0.15
        let dt = max(0.005, elapsedSeconds(since: t0))
        if sink == 0xDEADBEEF { print(sink) }
        return Double(totalOps) / dt
    }

    private func measureCPUMulti() -> Double {
        let workers = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let batch = 2_000_000
        let baseSeed = UInt64(DispatchTime.now().uptimeNanoseconds)
        let t0 = ContinuousClock.now
        var workerOps = [Int](repeating: 0, count: workers)
        var sinks = [UInt64](repeating: 0, count: workers)
        DispatchQueue.concurrentPerform(iterations: workers) { idx in
            var ops = 0
            var acc = baseSeed &+ UInt64(idx)
            let wt0 = ContinuousClock.now
            repeat {
                acc ^= self.cpuKernel(iterations: batch, seed: acc)
                ops += batch
            } while self.elapsedSeconds(since: wt0) < 0.15
            workerOps[idx] = ops
            sinks[idx] = acc
        }
        let dt = max(0.005, elapsedSeconds(since: t0))
        if sinks.reduce(0, ^) == 0xDEADBEEF { print("rare") }
        let totalOps = workerOps.reduce(0, +)
        return Double(totalOps) / dt
    }

    private func measureMemoryBandwidth() -> Double {
        let byteCount = 64 * 1_048_576
        let passes = 6
        var src = [UInt8](repeating: 0xA5, count: byteCount)
        var dst = [UInt8](repeating: 0x00, count: byteCount)

        let t0 = CFAbsoluteTimeGetCurrent()
        for p in 0..<passes {
            src[p] = UInt8(truncatingIfNeeded: p)
            src.withUnsafeBytes { sPtr in
                dst.withUnsafeMutableBytes { dPtr in
                    if let s = sPtr.baseAddress, let d = dPtr.baseAddress {
                        memcpy(d, s, byteCount)
                    }
                }
            }
        }
        let dt = max(0.0005, CFAbsoluteTimeGetCurrent() - t0)
        withExtendedLifetime(dst) {}
        let totalGB = Double(byteCount * passes) / 1_073_741_824.0
        return totalGB / dt
    }

    private func measureDiskIO(totalBytes: Int) throws -> (writeMBs: Double, readMBs: Double) {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-io-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let chunkSize = 1_048_576
        let chunk = [UInt8](repeating: 0x5A, count: chunkSize)
        let chunks = max(1, totalBytes / chunkSize)
        let actualBytes = chunks * chunkSize

        let wfd = open(fileURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard wfd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        _ = fcntl(wfd, F_NOCACHE, 1)

        let wt0 = CFAbsoluteTimeGetCurrent()
        chunk.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            for _ in 0..<chunks {
                _ = write(wfd, base, chunkSize)
            }
        }
        fsync(wfd)
        close(wfd)
        let wdt = max(0.001, CFAbsoluteTimeGetCurrent() - wt0)

        let rfd = open(fileURL.path, O_RDONLY)
        guard rfd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        _ = fcntl(rfd, F_NOCACHE, 1)

        var readBuf = [UInt8](repeating: 0, count: chunkSize)
        let rt0 = CFAbsoluteTimeGetCurrent()
        readBuf.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            while read(rfd, base, chunkSize) > 0 {}
        }
        close(rfd)
        let rdt = max(0.001, CFAbsoluteTimeGetCurrent() - rt0)

        let mb = Double(actualBytes) / 1_048_576.0
        return (mb / wdt, mb / rdt)
    }

    private func probeHTTP(url: URL) -> (latencyMs: Double?, statusCode: Int?) {
        let sem = DispatchSemaphore(value: 0)
        var latencyMs: Double?
        var statusCode: Int?

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 1.5
        let session = URLSession(configuration: config)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.5)
        req.httpMethod = "HEAD"
        let t0 = CFAbsoluteTimeGetCurrent()

        session.dataTask(with: req) { _, resp, err in
            if err == nil, let http = resp as? HTTPURLResponse {
                latencyMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                statusCode = http.statusCode
            }
            sem.signal()
        }.resume()

        _ = sem.wait(timeout: .now() + 1.7)
        session.invalidateAndCancel()
        return (latencyMs, statusCode)
    }
}
