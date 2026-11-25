import Foundation
import Darwin

public final class SystemTelemetryReader: @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    public init() {
        // Warm up CPU tick baseline immediately so first captureSnapshot() returns real CPU %
        if let raw = Self.readRawCPUTicks() {
            lock.lock()
            previousTicks = (raw.user, raw.system, raw.idle, raw.nice)
            lock.unlock()
        }
    }

    public static func getHardwareSpecs() -> HardwareSpecs {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var cpuBrand = ""
        if size > 0 {
            var data = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &data, &size, nil, 0) == 0 {
                cpuBrand = String(cString: data).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = ""
        if size > 0 {
            var data = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &data, &size, nil, 0) == 0 {
                model = String(cString: data).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let friendlyModel: String
        if model.hasPrefix("Mac14,3") || model.hasPrefix("Mac14,12") {
            friendlyModel = "Mac mini M2"
        } else if model.hasPrefix("Mac16,10") || model.hasPrefix("Mac16,11") {
            friendlyModel = "Mac mini M4"
        } else if model.hasPrefix("Macmini") || model.lowercased().contains("mini") {
            friendlyModel = "Mac mini"
        } else if model.lowercased().contains("book") {
            friendlyModel = "MacBook"
        } else if model.lowercased().contains("imac") {
            friendlyModel = "iMac"
        } else if model.lowercased().contains("studio") {
            friendlyModel = "Mac Studio"
        } else if model.lowercased().contains("pro") {
            friendlyModel = "Mac Pro"
        } else {
            friendlyModel = model.isEmpty ? "Mac" : model
        }

        var totalRAM: UInt64 = 0
        var ramSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalRAM, &ramSize, nil, 0)

        let coreCount = max(1, ProcessInfo.processInfo.processorCount)

        var totalDisk: UInt64 = 0
        let dataURL = URL(fileURLWithPath: "/System/Volumes/Data")
        let targetURL = FileManager.default.fileExists(atPath: dataURL.path) ? dataURL : URL(fileURLWithPath: "/")
        var st = statvfs()
        if statvfs(targetURL.path, &st) == 0 {
            totalDisk = UInt64(st.f_blocks) * UInt64(st.f_frsize)
        }

        return HardwareSpecs(
            modelName: friendlyModel,
            cpuBrand: cpuBrand,
            coreCount: coreCount,
            totalRAMBytes: totalRAM,
            totalDiskBytes: totalDisk
        )
    }

    public static func getHardwareModelName() -> String {
        let specs = getHardwareSpecs()
        if !specs.cpuBrand.isEmpty {
            return "\(specs.modelName) • \(specs.cpuBrand)"
        }
        return specs.modelName
    }

    public func captureSnapshot() throws -> SystemSnapshot {
        let cpu = readCPU()
        let memory = try readMemory()
        let disk = try readDisk()
        let thermal = readThermalLevel()
        let uptime = ProcessInfo.processInfo.systemUptime
        return SystemSnapshot(
            timestamp: Date(),
            cpu: cpu,
            memory: memory,
            disk: disk,
            thermalLevel: thermal,
            uptimeSeconds: uptime
        )
    }

    private func readThermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    private static func readRawCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64, coreCount: Int)? {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard kr == KERN_SUCCESS, let cpuInfo else { return nil }

        var userSum: UInt64 = 0
        var sysSum: UInt64 = 0
        var idleSum: UInt64 = 0
        var niceSum: UInt64 = 0

        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(numCPUs) {
            let base = i * stride
            userSum += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)]))
            sysSum  += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)]))
            idleSum += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)]))
            niceSum += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)]))
        }
        let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)

        return (userSum, sysSum, idleSum, niceSum, max(1, Int(numCPUs)))
    }

    private func readCPU() -> CPUMetrics {
        var loads = [Double](repeating: 0, count: 3)
        _ = Darwin.getloadavg(&loads, 3)

        lock.lock()
        let prev = previousTicks
        lock.unlock()

        var raw = Self.readRawCPUTicks()
        if prev == nil, let first = raw {
            lock.lock()
            previousTicks = (first.user, first.system, first.idle, first.nice)
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.12)
            raw = Self.readRawCPUTicks()
        }

        var userPct = 0.0
        var sysPct = 0.0
        var idlePct = 100.0
        let coreCount = raw?.coreCount ?? max(1, ProcessInfo.processInfo.processorCount)

        if let cur = raw {
            lock.lock()
            let baseline = previousTicks
            previousTicks = (cur.user, cur.system, cur.idle, cur.nice)
            lock.unlock()

            if let baseline {
                let dUser = cur.user >= baseline.user ? cur.user - baseline.user : 0
                let dSys = cur.system >= baseline.system ? cur.system - baseline.system : 0
                let dIdle = cur.idle >= baseline.idle ? cur.idle - baseline.idle : 0
                let dNice = cur.nice >= baseline.nice ? cur.nice - baseline.nice : 0
                let total = Double(dUser + dSys + dIdle + dNice)
                if total > 0 {
                    userPct = Double(dUser + dNice) / total * 100.0
                    sysPct = Double(dSys) / total * 100.0
                    idlePct = Double(dIdle) / total * 100.0
                }
            }
        }

        return CPUMetrics(
            userPercent: userPct,
            systemPercent: sysPct,
            idlePercent: idlePct,
            coreCount: coreCount,
            load1m: loads[0],
            load5m: loads[1],
            load15m: loads[2]
        )
    }

    private func readMemory() throws -> MemoryMetrics {
        var totalRAM: UInt64 = 0
        var ramSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalRAM, &ramSize, nil, 0)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            throw NSError(domain: "MacPulse.Telemetry", code: Int(kr), userInfo: [NSLocalizedDescriptionKey: "host_statistics64 failed"])
        }

        let pageSize = UInt64(vm_kernel_page_size)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        _ = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        // Activity Monitor-accurate memory breakdown:
        // App Memory = (internal_page_count - purgeable_count) * pageSize
        // Cached Files = (external_page_count + purgeable_count) * pageSize
        let internalPages = UInt64(vmStats.internal_page_count)
        let purgeablePages = UInt64(vmStats.purgeable_count)
        let externalPages = UInt64(vmStats.external_page_count)
        let appMemoryPages = internalPages >= purgeablePages ? (internalPages - purgeablePages) : 0
        let cachedFilePages = externalPages + purgeablePages

        return MemoryMetrics(
            totalBytes: totalRAM,
            activeBytes: UInt64(vmStats.active_count) * pageSize,
            inactiveBytes: UInt64(vmStats.inactive_count) * pageSize,
            wiredBytes: UInt64(vmStats.wire_count) * pageSize,
            compressedBytes: UInt64(vmStats.compressor_page_count) * pageSize,
            freeBytes: UInt64(vmStats.free_count) * pageSize,
            purgeableBytes: purgeablePages * pageSize,
            appMemoryBytes: appMemoryPages * pageSize,
            cachedFilesBytes: cachedFilePages * pageSize,
            swapTotalBytes: swap.xsu_total,
            swapUsedBytes: swap.xsu_used,
            swapins: vmStats.swapins,
            swapouts: vmStats.swapouts
        )
    }

    private func readDisk() throws -> DiskMetrics {
        let dataURL = URL(fileURLWithPath: "/System/Volumes/Data")
        let fallbackURL = URL(fileURLWithPath: "/")
        let targetURL = FileManager.default.fileExists(atPath: dataURL.path) ? dataURL : fallbackURL

        var stat = statvfs()
        guard statvfs(targetURL.path, &stat) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        let blockSize = UInt64(stat.f_frsize)
        let total = UInt64(stat.f_blocks) * blockSize

        let values = try? targetURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let availImportant = values?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
        let availRegular = values?.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
        let avail = availImportant ?? availRegular ?? (UInt64(stat.f_bavail) * blockSize)
        let used = total >= avail ? total - avail : 0

        return DiskMetrics(totalBytes: total, availableBytes: avail, usedBytes: used)
    }
}
