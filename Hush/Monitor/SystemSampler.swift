import Darwin
import Foundation

struct SystemReading {
    var appCPU: Double?
    var deviceCPU: Double?
    var memoryBytes: UInt64?
    var networkIn: Double?
    var networkOut: Double?
}

final class SystemSampler {
    private let host = mach_host_self()
    private let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNetwork: (received: UInt64, sent: UInt64, time: ContinuousClock.Instant)?

    func read(at now: ContinuousClock.Instant = .now) -> SystemReading {
        var reading = SystemReading()
        reading.appCPU = appCPU()
        reading.deviceCPU = deviceCPU()
        reading.memoryBytes = memoryFootprint()
        if let rates = networkRates(at: now) {
            reading.networkIn = rates.received
            reading.networkOut = rates.sent
        }
        return reading
    }

    private func appCPU() -> Double? {
        var threads: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return nil }
        defer {
            for index in 0..<Int(count) {
                mach_port_deallocate(mach_task_self_, threads[index])
            }
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threads)),
                vm_size_t(Int(count) * MemoryLayout<thread_t>.stride)
            )
        }

        var usage = 0.0
        for index in 0..<Int(count) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.stride / MemoryLayout<integer_t>.stride)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                usage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE)
            }
        }
        return min(100, usage / cores * 100)
    }

    private func deviceCPU() -> Double? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = load.cpu_ticks
        let busy = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3)
        let total = busy + UInt64(ticks.2)
        defer { lastTicks = (busy, total) }
        guard let lastTicks, total > lastTicks.total, busy >= lastTicks.busy else { return nil }
        return Double(busy - lastTicks.busy) / Double(total - lastTicks.total) * 100
    }

    private func memoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private func networkRates(at now: ContinuousClock.Instant) -> (received: Double, sent: Double)? {
        guard let totals = networkTotals() else { return nil }
        defer { lastNetwork = (totals.received, totals.sent, now) }
        guard let lastNetwork else { return nil }
        let seconds = lastNetwork.time.duration(to: now).seconds
        guard seconds > 0 else { return nil }
        let received = totals.received >= lastNetwork.received ? totals.received - lastNetwork.received : 0
        let sent = totals.sent >= lastNetwork.sent ? totals.sent - lastNetwork.sent : 0
        return (Double(received) / seconds, Double(sent) / seconds)
    }

    private func networkTotals() -> (received: UInt64, sent: UInt64)? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let address = entry.pointee
            guard let socket = address.ifa_addr, socket.pointee.sa_family == UInt8(AF_LINK), let data = address.ifa_data else { continue }
            let name = String(cString: address.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(stats.ifi_ibytes)
            sent += UInt64(stats.ifi_obytes)
        }
        return (received, sent)
    }
}
