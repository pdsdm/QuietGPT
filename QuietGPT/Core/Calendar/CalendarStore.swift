import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class CalendarStore {
    enum Access: Equatable {
        case unknown
        case full
        case writeOnly
        case denied
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded
    }

    let store = EKEventStore()
    private(set) var access: Access = .unknown
    private(set) var state: State = .idle
    private(set) var items: [CalendarItem] = []
    private(set) var range: DateInterval?
    private var observer: NSObjectProtocol?

    init() {
        refreshAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let range = self.range else { return }
                self.load(range, quietly: true)
            }
        }
    }

    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .full
        case .writeOnly: access = .writeOnly
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        refreshAccess()
    }

    func load(_ interval: DateInterval, quietly: Bool = false) {
        range = interval
        guard access == .full else { return }
        if !quietly { state = .loading }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        let events = store.events(matching: predicate)
        items = events.compactMap { event in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CalendarItem(id: event.calendarItemIdentifier + "|" + String(start.timeIntervalSince1970), title: title, start: start, end: max(end, start), allDay: event.isAllDay)
        }
        state = .loaded
    }

    func event(for item: CalendarItem) -> EKEvent? {
        let identifier = String(item.id.split(separator: "|").first ?? "")
        let predicate = store.predicateForEvents(withStart: item.start.addingTimeInterval(-1), end: item.end.addingTimeInterval(1), calendars: nil)
        return store.events(matching: predicate).first { $0.calendarItemIdentifier == identifier && $0.startDate == item.start }
    }

    func draft(on day: Date, calendar: Calendar) -> EKEvent {
        let event = EKEvent(eventStore: store)
        let now = Date()
        let base = calendar.isDate(day, inSameDayAs: now) ? now : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let start = calendar.nextDate(after: base, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? base
        event.startDate = calendar.isDate(day, inSameDayAs: now) ? start : base
        event.endDate = event.startDate.addingTimeInterval(3600)
        event.calendar = store.defaultCalendarForNewEvents
        return event
    }
}
