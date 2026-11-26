import Foundation

nonisolated struct CalendarItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
}

nonisolated struct PlacedItem: Equatable, Sendable {
    let item: CalendarItem
    let column: Int
    let columns: Int
}

nonisolated enum CalendarMath {
    static let dayStart = 8 * 60
    static let dayEnd = 22 * 60
    static let shortestFree = 30

    static func weekStart(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    static func timed(_ items: [CalendarItem], on day: Date, calendar: Calendar) -> [CalendarItem] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return items.filter { !$0.allDay && $0.end > start && $0.start < end }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    static func allDay(_ items: [CalendarItem], on day: Date, calendar: Calendar) -> [CalendarItem] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return items.filter { $0.allDay && $0.end > start && $0.start < end }
    }

    static func busy(_ items: [CalendarItem], on day: Date, calendar: Calendar) -> [ClosedRange<Int>] {
        let start = calendar.startOfDay(for: day)
        var ranges = timed(items, on: day, calendar: calendar).map { item -> ClosedRange<Int> in
            let from = max(0, Int(item.start.timeIntervalSince(start) / 60))
            let to = min(24 * 60, Int(item.end.timeIntervalSince(start) / 60))
            return from...max(from, to)
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Int>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    static func busyMinutes(_ items: [CalendarItem], on day: Date, calendar: Calendar) -> Int {
        busy(items, on: day, calendar: calendar).reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    }

    static func free(_ items: [CalendarItem], on day: Date, calendar: Calendar) -> [ClosedRange<Int>] {
        var cursor = dayStart
        var slots: [ClosedRange<Int>] = []
        for range in busy(items, on: day, calendar: calendar) {
            if range.upperBound <= cursor { continue }
            if range.lowerBound >= dayEnd { break }
            if range.lowerBound - cursor >= shortestFree {
                slots.append(cursor...range.lowerBound)
            }
            cursor = max(cursor, range.upperBound)
        }
        if dayEnd - cursor >= shortestFree {
            slots.append(cursor...dayEnd)
        }
        return slots
    }

    static func meter(busyMinutes: Int, rows: Int) -> [Character] {
        let ramp = AsciiGlyphs.ramp
        let level = Double(min(busyMinutes, dayEnd - dayStart)) / Double(dayEnd - dayStart) * Double(rows)
        return (0..<rows).map { row in
            let fill = min(1, max(0, level - Double(row)))
            if busyMinutes > 0, row == 0, fill < 0.2 { return ramp[1] }
            return ramp[Int((fill * Double(ramp.count - 1)).rounded())]
        }
    }

    static func placed(_ items: [CalendarItem]) -> [PlacedItem] {
        var result: [PlacedItem] = []
        var group: [CalendarItem] = []
        var groupEnd = Date.distantPast
        func flush() {
            var lanes: [Date] = []
            var lane: [String: Int] = [:]
            for item in group {
                if let free = lanes.firstIndex(where: { $0 <= item.start }) {
                    lanes[free] = item.end
                    lane[item.id] = free
                } else {
                    lanes.append(item.end)
                    lane[item.id] = lanes.count - 1
                }
            }
            result += group.map { PlacedItem(item: $0, column: lane[$0.id] ?? 0, columns: lanes.count) }
            group = []
        }
        for item in items.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if !group.isEmpty, item.start >= groupEnd {
                flush()
            }
            group.append(item)
            groupEnd = group.count == 1 ? item.end : max(groupEnd, item.end)
        }
        flush()
        return result
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60)
    }

    static func length(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
