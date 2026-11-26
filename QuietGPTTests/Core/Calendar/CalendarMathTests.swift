import Foundation
import Testing
@testable import QuietGPT

struct CalendarMathTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func item(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarItem {
        CalendarItem(id: id, title: id, start: start, end: end, allDay: allDay)
    }

    @Test func weekStartsOnTheFirstWeekday() {
        #expect(CalendarMath.weekStart(for: time(26, 15), calendar: calendar) == time(23, 0))
        #expect(CalendarMath.weekStart(for: time(23, 0), calendar: calendar) == time(23, 0))
        #expect(CalendarMath.weekStart(for: time(29, 23), calendar: calendar) == time(23, 0))
    }

    @Test func busyTimeMergesOverlapsAndClipsToTheDay() {
        let items = [
            item("a", time(16, 9, 30), time(16, 10, 15)),
            item("b", time(16, 10), time(16, 11)),
            item("c", time(15, 23), time(16, 1)),
            item("d", time(16, 0), time(17, 0), allDay: true),
        ]

        #expect(CalendarMath.busy(items, on: time(16, 12), calendar: calendar) == [0...60, 570...660])
        #expect(CalendarMath.busyMinutes(items, on: time(16, 12), calendar: calendar) == 150)
        #expect(CalendarMath.allDay(items, on: time(16, 12), calendar: calendar).map(\.id) == ["d"])
    }

    @Test func freeTimeMatchesTheToolRule() {
        let items = [
            item("bank", time(16, 9, 30), time(16, 10, 15)),
            item("lunch", time(16, 13), time(16, 14)),
            item("padel", time(16, 18), time(16, 19, 30)),
            item("short", time(16, 19, 45), time(16, 21, 40)),
        ]

        #expect(CalendarMath.free(items, on: time(16, 0), calendar: calendar) == [480...570, 615...780, 840...1080])
        #expect(CalendarMath.free([], on: time(16, 0), calendar: calendar) == [480...1320])
    }

    @Test func meterFillsFromTheBottom() {
        #expect(CalendarMath.meter(busyMinutes: 0, rows: 3) == [" ", " ", " "])
        #expect(CalendarMath.meter(busyMinutes: 10, rows: 3) == [".", " ", " "])
        #expect(CalendarMath.meter(busyMinutes: 840, rows: 3) == ["@", "@", "@"])
        #expect(CalendarMath.meter(busyMinutes: 420, rows: 3) == ["@", "+", " "])
    }

    @Test func overlappingEventsShareColumns() {
        let items = [
            item("a", time(16, 9), time(16, 11)),
            item("b", time(16, 10), time(16, 12)),
            item("c", time(16, 11), time(16, 12)),
            item("d", time(16, 14), time(16, 15)),
        ]
        let placed = Dictionary(uniqueKeysWithValues: CalendarMath.placed(items).map { ($0.item.id, ($0.column, $0.columns)) })

        #expect(placed["a"]! == (0, 2))
        #expect(placed["b"]! == (1, 2))
        #expect(placed["c"]! == (0, 2))
        #expect(placed["d"]! == (0, 1))
    }

    @Test func formatsTimesAndLengths() {
        #expect(CalendarMath.clock(570) == "09:30")
        #expect(CalendarMath.length(45) == "45 min")
        #expect(CalendarMath.length(120) == "2 h")
        #expect(CalendarMath.length(135) == "2 h 15 min")
    }
}
