import SwiftUI

struct ArrivalAttribute: TextAttribute {
    let time: TimeInterval
}

struct ArrivalRenderer: TextRenderer {
    var now: TimeInterval
    var duration: TimeInterval = 0.45
    var stagger: TimeInterval = 0.012

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let arrival = run[ArrivalAttribute.self] else {
                    context.draw(run)
                    continue
                }
                for (index, glyph) in run.enumerated() {
                    let age = now - arrival.time - Double(index) * stagger
                    let progress = min(1, max(0, age / duration))
                    let eased = 1 - pow(1 - progress, 3)
                    var copy = context
                    copy.opacity = eased
                    copy.translateBy(x: 0, y: (1 - eased) * 5)
                    copy.draw(glyph)
                }
            }
        }
    }
}

struct StreamingText: View {
    let text: String
    let arrivals: [StreamArrival]
    let offset: Int
    var font: Font = QuietGPTFont.body
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            composed(now: context.date.timeIntervalSinceReferenceDate)
                .font(font)
                .foregroundStyle(color)
                .textRenderer(ArrivalRenderer(now: reduceMotion ? .greatestFiniteMagnitude : context.date.timeIntervalSinceReferenceDate))
        }
    }

    private func composed(now: TimeInterval) -> Text {
        let characters = Array(text)
        let fresh = arrivals
            .filter { now - $0.time < 1.2 }
            .map { (offset: $0.offset - offset, time: $0.time) }
            .filter { $0.offset >= 0 && $0.offset < characters.count }

        var segments: [(range: Range<Int>, time: TimeInterval?)] = []
        var start = 0
        for (index, arrival) in fresh.enumerated() {
            if arrival.offset > start {
                segments.append((start..<arrival.offset, nil))
            }
            let lower = max(arrival.offset, start)
            let upper = index + 1 < fresh.count ? fresh[index + 1].offset : characters.count
            if upper > lower {
                segments.append((lower..<upper, arrival.time))
            }
            start = max(start, upper)
        }
        if start < characters.count {
            segments.append((start..<characters.count, nil))
        }

        return segments.reduce(Text("")) { partial, segment in
            let piece = Text(String(characters[segment.range]))
            let styled = segment.time.map { piece.customAttribute(ArrivalAttribute(time: $0)) } ?? piece
            return Text("\(partial)\(styled)")
        }
    }
}

struct StreamArrival: Equatable {
    let offset: Int
    let time: TimeInterval
}

struct StreamCursor: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let blink = 0.55

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.blink)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / Self.blink)
            Capsule()
                .fill(palette.accent)
                .frame(width: 3, height: 18)
                .opacity(reduceMotion || step % 2 == 0 ? 1 : 0.2)
        }
        .accessibilityHidden(true)
    }
}

struct ThinkingGlyphs: View {
    @Environment(\.palette) private var palette

    private static let ramp: [Character] = Array(" .·:=*")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 14)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Text(String((0..<7).map { index in
                let wave = 0.5 + 0.5 * sin(t * 5 - Double(index) * 0.8)
                return Self.ramp[min(Self.ramp.count - 1, Int(wave * Double(Self.ramp.count)))]
            }))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(palette.accent)
        }
        .accessibilityLabel("QuietGPT is thinking")
    }
}
