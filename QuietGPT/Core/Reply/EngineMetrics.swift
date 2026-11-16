import Foundation

nonisolated struct EngineMetrics: Sendable {
    var loadSeconds: Double?
    var promptTokens = 0
    var reusedTokens = 0
    var prefillSeconds = 0.0
    var firstTokenSeconds: Double?
    var generatedTokens = 0
    var decodeSeconds = 0.0
    var footprintMB = 0
    var peakMB = 0
    var thermal = ""

    var summary: String {
        let load = loadSeconds.map { String(format: "load %.2f s · ", $0) } ?? ""
        let prefillRate = prefillSeconds > 0 ? Double(promptTokens - reusedTokens) / prefillSeconds : 0
        let decodeRate = decodeSeconds > 0 ? Double(generatedTokens) / decodeSeconds : 0
        let first = firstTokenSeconds.map { String(format: "%.2f s", $0) } ?? "-"
        return load
            + "prompt \(promptTokens) tok (reused \(reusedTokens)) · "
            + String(format: "prefill %.2f s (%.0f tok/s) · ", prefillSeconds, prefillRate)
            + "first token \(first) · "
            + String(format: "decode %d tok at %.1f tok/s · ", generatedTokens, decodeRate)
            + "memory \(footprintMB) MB, peak \(peakMB) MB · thermal \(thermal)"
    }

    static func memory() -> (Int, Int) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (Int(info.phys_footprint >> 20), Int(info.ledger_phys_footprint_peak >> 20))
    }

    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
