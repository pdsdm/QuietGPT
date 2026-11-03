import Charts
import SwiftUI

struct MonitorPanel: View {
    var controller: ChatController
    var onClose: () -> Void

    @Environment(\.palette) private var palette
    @State private var store = MonitorStore()

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            LazyVGrid(columns: columns, spacing: 8) {
                neuralTile
                cpuTile
                gpuTile
                memoryTile
                networkTile
                powerTile
            }
        }
        .padding(12)
        .background(palette.surface, in: .rect(cornerRadius: Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        }
        .onAppear { store.start(reading: controller) }
        .onDisappear { store.stop() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: controller.isResponding ? palette.accent : palette.local, size: 6)
            Text("monitor")
                .font(HushFont.mono)
                .foregroundStyle(palette.text)
            Text("live · \(MonitorStore.interval.seconds.formatted()) s")
                .font(HushFont.monoSmall)
                .foregroundStyle(palette.text3)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.text2)
                    .frame(width: 26, height: 26)
                    .background(palette.elevated, in: .circle)
            }
            .buttonStyle(PressableStyle(scale: 0.86))
            .accessibilityLabel("Close monitor")
        }
    }

    private var neuralTile: some View {
        let rate = store.latest?.tokensPerSecond ?? 0
        let value = controller.isResponding ? "\(Int(rate.rounded())) tok/s" : "idle"
        let detail = controller.lastMetrics.flatMap { metrics in
            metrics.tokensPerSecond.map { "last \(Int($0.rounded())) tok/s" }
        } ?? "no replies yet"
        return MonitorTile(label: "neural engine", value: value, detail: detail) {
            Sparkline(series: [.init(values: store.samples.map(\.tokensPerSecond), color: palette.accent)], floor: 40)
        }
    }

    private var cpuTile: some View {
        let app = store.latest?.appCPU ?? 0
        let device = store.latest?.deviceCPU ?? 0
        return MonitorTile(label: "cpu", value: "\(Int(app.rounded()))% QuietGPT", detail: "\(Int(device.rounded()))% iphone") {
            Sparkline(
                series: [
                    .init(values: store.samples.map(\.deviceCPU), color: palette.text3),
                    .init(values: store.samples.map(\.appCPU), color: palette.local)
                ],
                floor: 100
            )
        }
    }

    private var gpuTile: some View {
        let rate = store.latest?.framesPerSecond ?? 0
        return MonitorTile(label: "gpu", value: "\(Int(rate.rounded())) fps", detail: "interface frames") {
            Sparkline(series: [.init(values: store.samples.map(\.framesPerSecond), color: palette.accentText)], floor: 120)
        }
    }

    private var memoryTile: some View {
        let bytes = store.latest?.memoryBytes ?? 0
        return MonitorTile(label: "memory", value: Self.bytes(bytes), detail: "used by QuietGPT") {
            Sparkline(series: [.init(values: store.samples.map(\.memoryBytes), color: palette.text2)], floor: 1)
        }
    }

    private var networkTile: some View {
        let received = store.latest?.networkIn ?? 0
        let sent = store.latest?.networkOut ?? 0
        return MonitorTile(
            label: "network",
            value: "↓\(Self.bytes(received))/s ↑\(Self.bytes(sent))/s",
            detail: "QuietGPT sends 0 B"
        ) {
            Sparkline(
                series: [
                    .init(values: store.samples.map(\.networkIn), color: palette.local),
                    .init(values: store.samples.map(\.networkOut), color: palette.danger)
                ],
                floor: 1024
            )
        }
    }

    private var powerTile: some View {
        let battery = store.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "-"
        return MonitorTile(
            label: "power",
            value: Self.thermalName(store.thermalState),
            detail: "battery \(battery)\(store.lowPower ? " · low power" : "")"
        ) {
            ThermalBar(level: Self.thermalLevel(store.thermalState))
        }
    }

    private static func bytes(_ value: Double) -> String {
        Int64(value).formatted(.byteCount(style: .memory))
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "cool"
        case .fair: "warm"
        case .serious: "hot"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func thermalLevel(_ state: ProcessInfo.ThermalState) -> Int {
        switch state {
        case .nominal: 1
        case .fair: 2
        case .serious: 3
        case .critical: 4
        @unknown default: 0
        }
    }
}

private struct MonitorTile<Graph: View>: View {
    let label: String
    let value: String
    let detail: String
    @ViewBuilder let graph: Graph

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(HushFont.monoSmall)
                    .foregroundStyle(palette.text3)
                Spacer(minLength: 4)
                Text(value)
                    .font(HushFont.monoSmall)
                    .foregroundStyle(palette.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            graph
                .frame(height: 24)
            Text(detail)
                .font(HushFont.caption)
                .foregroundStyle(palette.text3)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.raised, in: .rect(cornerRadius: Radius.medium, style: .continuous))
        .animation(Motion.snappy, value: value)
    }
}

private struct Sparkline: View {
    struct Series {
        let values: [Double]
        let color: Color
    }

    let series: [Series]
    let floor: Double

    var body: some View {
        let top = max(floor, series.flatMap(\.values).max() ?? 0) * 1.1
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { index, line in
                ForEach(Array(line.values.enumerated()), id: \.offset) { position, value in
                    AreaMark(
                        x: .value("Time", position),
                        y: .value("Value", value),
                        series: .value("Series", index),
                        stacking: .unstacked
                    )
                    .foregroundStyle(line.color.opacity(0.14).gradient)
                    .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Time", position),
                        y: .value("Value", value),
                        series: .value("Series", index)
                    )
                    .foregroundStyle(line.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...(MonitorStore.capacity - 1))
        .chartYScale(domain: 0...top)
    }
}

private struct ThermalBar: View {
    let level: Int

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...4, id: \.self) { step in
                Capsule()
                    .fill(step <= level ? color(for: step) : palette.elevated)
                    .frame(height: 6)
            }
        }
        .frame(maxHeight: .infinity)
        .animation(Motion.spring, value: level)
    }

    private func color(for step: Int) -> Color {
        switch step {
        case 1: palette.local
        case 2: palette.accent
        default: palette.danger
        }
    }
}
