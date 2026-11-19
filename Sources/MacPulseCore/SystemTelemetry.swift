import Foundation
import Darwin

public final class SystemTelemetryReader {
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    public init() {}

    public static func getHardwareModelName() -> String {
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

        if !cpuBrand.isEmpty {
            return "\(friendlyModel) • \(cpuBrand)"
        }
        return friendlyModel
    }

    public func captureSnapshot() throws -> SystemSnapshot {
        let cpu = readCPU()
        let memory = try readMemory()
        let disk = try readDisk()
        return SystemSnapshot(timestamp: Date(), cpu: cpu, memory: memory, disk: disk)
    }

    private func readCPU() -> CPUMetrics {
        var loads = [Double](repeating: 0, count: 3)
        _ = Darwin.getloadavg(&loads, 3)

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

        var userSum: UInt64 = 0
        var sysSum: UInt64 = 0
        var idleSum: UInt64 = 0
        var niceSum: UInt64 = 0

        if kr == KERN_SUCCESS, let cpuInfo {
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
        }

        var userPct = 0.0
        var sysPct = 0.0
        var idlePct = 100.0

        if let prev = previousTicks {
            let dUser = userSum >= prev.user ? userSum - prev.user : 0
            let dSys = sysSum >= prev.system ? sysSum - prev.system : 0
            let dIdle = idleSum >= prev.idle ? idleSum - prev.idle : 0
            let dNice = niceSum >= prev.nice ? niceSum - prev.nice : 0
            let total = Double(dUser + dSys + dIdle + dNice)
            if total > 0 {
                userPct = Double(dUser + dNice) / total * 100.0
                sysPct = Double(dSys) / total * 100.0
                idlePct = Double(dIdle) / total * 100.0
            }
        }
        previousTicks = (userSum, sysSum, idleSum, niceSum)

        return CPUMetrics(
            userPercent: userPct,
            systemPercent: sysPct,
            idlePercent: idlePct,
            coreCount: max(1, Int(numCPUs)),
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

        return MemoryMetrics(
            totalBytes: totalRAM,
            activeBytes: UInt64(vmStats.active_count) * pageSize,
            inactiveBytes: UInt64(vmStats.inactive_count) * pageSize,
            wiredBytes: UInt64(vmStats.wire_count) * pageSize,
            compressedBytes: UInt64(vmStats.compressor_page_count) * pageSize,
            freeBytes: UInt64(vmStats.free_count) * pageSize,
            purgeableBytes: UInt64(vmStats.purgeable_count) * pageSize,
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
