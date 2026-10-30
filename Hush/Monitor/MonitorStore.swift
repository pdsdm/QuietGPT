import Foundation
import Observation
import UIKit

@Observable
final class MonitorStore {
    struct Sample: Identifiable {
        let id: Int
        let tokensPerSecond: Double
        let appCPU: Double
        let deviceCPU: Double
        let framesPerSecond: Double
        let memoryBytes: Double
        let networkIn: Double
        let networkOut: Double
    }

    static let capacity = 60
    static let interval = Duration.milliseconds(500)

    private(set) var samples: [Sample] = []
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var batteryLevel: Float?
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private let sampler = SystemSampler()
    private let frames = FrameMeter()
    private var task: Task<Void, Never>?
    private var nextID = 0

    var latest: Sample? { samples.last }

    func start(reading controller: ChatController) {
        guard task == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        frames.start()
        _ = sampler.read()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self else { return }
                self.record(from: controller)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        frames.stop()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func record(from controller: ChatController) {
        let reading = sampler.read()
        let sample = Sample(
            id: nextID,
            tokensPerSecond: controller.liveMetrics?.rate(until: .now) ?? 0,
            appCPU: reading.appCPU ?? latest?.appCPU ?? 0,
            deviceCPU: reading.deviceCPU ?? latest?.deviceCPU ?? 0,
            framesPerSecond: frames.take(),
            memoryBytes: reading.memoryBytes.map { Double($0) } ?? latest?.memoryBytes ?? 0,
            networkIn: reading.networkIn ?? 0,
            networkOut: reading.networkOut ?? 0
        )
        nextID += 1
        samples.append(sample)
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }

        thermalState = ProcessInfo.processInfo.thermalState
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let level = UIDevice.current.batteryLevel
        batteryLevel = level >= 0 ? level : nil
    }
}
