#if DEBUG
import EventKit
import Foundation

enum DebugLaunch {
    private static let sampleReply = """
    Here are three small changes that help most people sleep better:

    - **Keep one wake time**, also on weekends.
    - Dim the lights and put the phone away an hour before bed.
    - Keep the room cool, dark and quiet.

    Give it two weeks. Most people notice a change by then.
    """

    private enum Key: String {
        case monitor = "QuietGPTMonitor"
        case focus = "QuietGPTFocus"
        case tab = "QuietGPTTab"
        case simulate = "QuietGPTSimulate"
        case prompt = "QuietGPTPrompt"
        case engine = "QuietGPTEngine"
        case weights = "QuietGPTWeights"
        case prompts = "QuietGPTPrompts"
        case eval = "QuietGPTEval"
        case computePlan = "QuietGPTComputePlan"
        case longChat = "QuietGPTLongChat"
        case seedCalendar = "QuietGPTSeedCalendar"
    }

    static var weights: String? {
        UserDefaults.standard.string(forKey: Key.weights.rawValue)
    }

    static var engine: TextEngineKind? {
        UserDefaults.standard.string(forKey: Key.engine.rawValue).flatMap(TextEngineKind.init(rawValue:))
    }

    static var opensMonitor: Bool {
        UserDefaults.standard.bool(forKey: Key.monitor.rawValue)
    }

    static var focusesComposer: Bool {
        UserDefaults.standard.bool(forKey: Key.focus.rawValue)
    }

    static func apply(controller: ChatController, tab: inout AppTab) {
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: Key.tab.rawValue), let launchTab = AppTab(rawValue: name) {
            tab = launchTab
        }
        if defaults.bool(forKey: Key.simulate.rawValue) {
            controller.simulateReplies(with: sampleReply)
        }
        if let prompt = defaults.string(forKey: Key.prompt.rawValue), !prompt.isEmpty {
            controller.send(prompt)
        }
        if DebugEval.isPlanned {
            tab = .keyboard
            Task { await DebugEval.runPlan() }
        }
        if DebugBattery.isPlanned {
            tab = .keyboard
            Task { await DebugBattery.run() }
        }
        if defaults.bool(forKey: Key.computePlan.rawValue) {
            Task.detached { await CoreMLPlanReport.run(compiledFolder: CoreMLTextEngine.compiledFolder) }
        }
        #if targetEnvironment(simulator)
        if defaults.bool(forKey: Key.seedCalendar.rawValue) {
            seedCalendar()
        }
        #endif
        if defaults.bool(forKey: Key.longChat.rawValue) {
            Task { await DebugLongChat.run() }
        }
        if let sets = defaults.string(forKey: Key.eval.rawValue), !sets.isEmpty {
            Task { await DebugEval.run(sets: sets.components(separatedBy: ",")) }
        }
        if let script = defaults.string(forKey: Key.prompts.rawValue), !script.isEmpty {
            let prompts = script.components(separatedBy: "||")
            Task {
                for prompt in prompts {
                    while controller.isResponding {
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    controller.send(prompt)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    #if targetEnvironment(simulator)
    private static func seedCalendar() {
        let store = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, let target = store.defaultCalendarForNewEvents else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let week = CalendarMath.weekStart(for: today, calendar: calendar)
        let existing = store.events(matching: store.predicateForEvents(withStart: week, end: week.addingTimeInterval(14 * 86_400), calendars: [target]))
        guard existing.isEmpty else { return }
        let plan: [(day: Int, hour: Int, minute: Int, minutes: Int, title: String)] = [
            (0, 9, 30, 45, "Bank appointment"), (0, 13, 0, 60, "Lunch with Marta"), (0, 18, 0, 90, "Padel"),
            (1, 17, 30, 60, "Parents' meeting at school"), (2, 8, 0, 480, "Workshop"), (2, 12, 0, 30, "Call with the accountant"),
            (3, 10, 0, 60, "Dentist"), (3, 10, 30, 60, "Design review"), (3, 16, 0, 45, "Run"), (3, 19, 0, 120, "Cinema"),
            (4, 11, 0, 30, "Call with Ana"), (5, 10, 0, 120, "Bike ride"), (8, 9, 0, 60, "Team planning"),
        ]
        for entry in plan {
            guard let day = calendar.date(byAdding: .day, value: entry.day, to: week), let start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day) else { continue }
            let event = EKEvent(eventStore: store)
            event.calendar = target
            event.title = entry.title
            event.startDate = start
            event.endDate = start.addingTimeInterval(Double(entry.minutes) * 60)
            try? store.save(event, span: .thisEvent, commit: false)
        }
        if let day = calendar.date(byAdding: .day, value: 4, to: week) {
            let event = EKEvent(eventStore: store)
            event.calendar = target
            event.title = "Marc's birthday"
            event.isAllDay = true
            event.startDate = day
            event.endDate = day
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
    #endif
}
#endif
