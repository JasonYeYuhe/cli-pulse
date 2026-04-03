#if os(macOS)
import Foundation
import Darwin

/// Collects device-level metrics (CPU, memory) using kernel APIs.
/// Runs outside the sandbox in the Login Item helper.
public enum DeviceMetrics {

    public struct Snapshot: Sendable {
        public let cpuUsage: Int    // 0-100%
        public let memoryUsage: Int // 0-100%

        public init(cpuUsage: Int, memoryUsage: Int) {
            self.cpuUsage = cpuUsage
            self.memoryUsage = memoryUsage
        }
    }

    /// Collect current device CPU and memory usage.
    /// Falls back to 0 for either metric on failure.
    public static func collect() -> Snapshot {
        Snapshot(cpuUsage: collectCPU(), memoryUsage: collectMemory())
    }

    // MARK: - CPU via getloadavg

    /// Returns CPU usage percentage based on 1-minute load average.
    /// Matches Python's `os.getloadavg()[0] / cpu_count * 100`.
    static func collectCPU() -> Int {
        var loadavg = [Double](repeating: 0, count: 3)
        guard getloadavg(&loadavg, 3) != -1 else { return 0 }
        let cpuCount = max(ProcessInfo.processInfo.processorCount, 1)
        let pct = Int((loadavg[0] / Double(cpuCount)) * 100.0)
        return min(max(pct, 0), 100)
    }

    // MARK: - Memory via Mach host_statistics64

    /// Returns memory usage percentage using the Mach VM info API.
    /// This is a direct kernel call — no subprocess needed (unlike Python's vm_stat parsing).
    static func collectMemory() -> Int {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let hostPort = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, hostPort) }

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(info.active_count) * pageSize
        let wired = UInt64(info.wire_count) * pageSize
        let compressed = UInt64(info.compressor_page_count) * pageSize
        // speculative pages are "free" but mapped; exclude from used
        let used = active + wired + compressed

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return 0 }

        let pct = Int((Double(used) / Double(totalBytes)) * 100.0)
        return min(max(pct, 0), 100)
    }
}
#endif
