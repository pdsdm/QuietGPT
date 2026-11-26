import EventKit
import SwiftUI

struct CalendarScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var store = CalendarStore()
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var week = 0
    @State private var opened: CalendarItem?
    @State private var creating = false

    private let calendar = Calendar.current
    private static let span = 104

    private var thisWeek: Date {
        CalendarMath.weekStart(for: .now, calendar: calendar)
    }

    private func weekStart(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset * 7, to: thisWeek) ?? thisWeek
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            switch store.access {
            case .full:
                content
            case .unknown:
                CalendarAccessView(
                    title: "Your day, on this iPhone",
                    message: "QuietGPT reads your calendar on this iPhone to show your events and your free time. Your events never leave the device.",
                    action: "Allow calendar access"
                ) {
                    Task {
                        await store.requestAccess()
                        reload()
                    }
                }
            case .writeOnly:
                CalendarAccessView(
                    title: "QuietGPT can't read your calendar",
                    message: "QuietGPT can add events, but it can't read them. In Settings, choose Full Access to see your day here.",
                    action: "Open Settings",
                    run: openSettings
                )
            case .denied:
                CalendarAccessView(
                    title: "Calendar access is off",
                    message: "Turn on Full Access in Settings to see your events here. QuietGPT reads them only on this iPhone.",
                    action: "Open Settings",
                    run: openSettings
                )
            }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.refreshAccess()
            reload()
        }
        .onChange(of: week) { old, new in
            let offset = calendar.dateComponents([.day], from: weekStart(old), to: selected).day ?? 0
            let today = calendar.startOfDay(for: .now)
            let moved = calendar.date(byAdding: .day, value: min(max(offset, 0), 6), to: weekStart(new)) ?? weekStart(new)
            selected = new == 0 ? today : moved
            reload()
        }
        .sheet(item: $opened) { item in
            if let event = store.event(for: item) {
                EventDetailSheet(event: event) { opened = nil }
                    .ignoresSafeArea()
            } else {
                Text("This event is no longer in your calendar.")
                    .font(QuietGPTFont.callout)
                    .foregroundStyle(palette.text2)
                    .padding(24)
                    .presentationDetents([.height(160)])
            }
        }
        .sheet(isPresented: $creating) {
            EventEditSheet(store: store.store, event: store.draft(on: selected, calendar: calendar)) { creating = false }
                .ignoresSafeArea()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 24)

            TabView(selection: $week) {
                ForEach(-Self.span...Self.span, id: \.self) { offset in
                    WeekRow(start: weekStart(offset), selected: selected, items: store.items, calendar: calendar) { day in
                        withAnimation(Motion.snappy) { selected = day }
                    }
                    .padding(.horizontal, 14)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 96)
            .padding(.top, 14)

            DaySummary(day: selected, items: store.items, calendar: calendar) { opened = $0 }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)

            Rectangle()
                .fill(palette.line)
                .frame(height: 1)

            DayTimeline(day: selected, items: store.items, loading: store.state == .loading, calendar: calendar) { opened = $0 }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.formatted(.dateTime.weekday(.wide)).localizedCapitalized)
                    .font(QuietGPTFont.largeTitle)
                    .foregroundStyle(palette.text)
                    .contentTransition(.opacity)
                Text(selected.formatted(.dateTime.day().month(.wide).year()))
                    .font(QuietGPTFont.subheadline)
                    .foregroundStyle(palette.text2)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if !calendar.isDateInToday(selected) {
                Button("Today") {
                    withAnimation(Motion.spring) {
                        week = 0
                        selected = calendar.startOfDay(for: .now)
                    }
                }
                .font(QuietGPTFont.callout)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(palette.raised, in: .rect(cornerRadius: Radius.small, style: .continuous))
                .buttonStyle(PressableStyle())
                .transition(.opacity)
            }
            Button {
                creating = true
            } label: {
                Image(systemName: "plus")
                    .accessibilityHidden(true)
            }
            .buttonStyle(CircleIconButtonStyle(filled: true))
            .accessibilityLabel("New event")
        }
        .animation(Motion.snappy, value: calendar.isDateInToday(selected))
    }

    private func reload() {
        let start = weekStart(week - 1)
        let end = weekStart(week + 2)
        store.load(DateInterval(start: start, end: end))
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

private struct WeekRow: View {
    let start: Date
    let selected: Date
    let items: [CalendarItem]
    let calendar: Calendar
    let select: (Date) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
                DayCell(
                    day: day,
                    selected: calendar.isDate(day, inSameDayAs: selected),
                    today: calendar.isDateInToday(day),
                    busy: CalendarMath.busyMinutes(items, on: day, calendar: calendar),
                    allDay: !CalendarMath.allDay(items, on: day, calendar: calendar).isEmpty
                ) {
                    select(day)
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let selected: Bool
    let today: Bool
    let busy: Int
    let allDay: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    private var meter: String {
        CalendarMath.meter(busyMinutes: busy == 0 && allDay ? 1 : busy, rows: 3).reversed().map { String(repeating: $0, count: 3) }.joined(separator: "\n")
    }

    private var label: String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let planned = busy > 0 ? String(localized: "\(CalendarMath.length(busy)) planned") : allDay ? String(localized: "all-day event") : String(localized: "nothing planned")
        return today ? String(localized: "Today, \(date), \(planned)") : "\(date), \(planned)"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(QuietGPTFont.caption)
                    .foregroundStyle(palette.text3)
                Text(day.formatted(.dateTime.day()))
                    .font(QuietGPTFont.headline)
                    .monospacedDigit()
                    .foregroundStyle(selected ? palette.onPrimary : palette.text)
                    .frame(width: 38, height: 38)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                .fill(palette.primary)
                        } else if today {
                            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                .strokeBorder(palette.text, lineWidth: 1.5)
                        }
                    }
                Text(meter)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .lineSpacing(-1)
                    .foregroundStyle(selected ? palette.text : palette.text2)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DaySummary: View {
    let day: Date
    let items: [CalendarItem]
    let calendar: Calendar
    let open: (CalendarItem) -> Void

    @Environment(\.palette) private var palette

    private var text: String {
        let timed = CalendarMath.timed(items, on: day, calendar: calendar)
        let longest = CalendarMath.free(items, on: day, calendar: calendar).max { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }
        let free: String
        if let longest {
            free = longest.lowerBound == CalendarMath.dayStart && longest.upperBound == CalendarMath.dayEnd
                ? String(localized: "Free from 08:00 to 22:00.")
                : String(localized: "Longest free time: \(CalendarMath.clock(longest.lowerBound)) to \(CalendarMath.clock(longest.upperBound)).")
        } else {
            free = String(localized: "No free time from 08:00 to 22:00.")
        }
        guard !timed.isEmpty else { return String(localized: "Nothing planned.") + " " + free }
        let count = timed.count == 1 ? String(localized: "1 event") : String(localized: "\(timed.count) events")
        return count + ", " + String(localized: "\(CalendarMath.length(CalendarMath.busyMinutes(items, on: day, calendar: calendar))) planned.") + " " + free
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(QuietGPTFont.footnote)
                .foregroundStyle(palette.text2)
                .contentTransition(.opacity)
            let allDay = CalendarMath.allDay(items, on: day, calendar: calendar)
            if !allDay.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(allDay) { item in
                            Button {
                                open(item)
                            } label: {
                                Chip(title: item.title.isEmpty ? String(localized: "No title") : item.title)
                            }
                            .buttonStyle(PressableStyle())
                            .frame(minHeight: 44)
                            .accessibilityLabel(String(localized: "All day: \(item.title)"))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct DayTimeline: View {
    let day: Date
    let items: [CalendarItem]
    let loading: Bool
    let calendar: Calendar
    let open: (CalendarItem) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 56

    private let gutter: CGFloat = 52

    private var target: Int {
        if calendar.isDateInToday(day) {
            let now = calendar.dateComponents([.hour], from: .now).hour ?? 8
            return max(0, now - 1)
        }
        if let first = CalendarMath.timed(items, on: day, calendar: calendar).first {
            return max(0, (calendar.isDate(first.start, inSameDayAs: day) ? calendar.component(.hour, from: first.start) : 0) - 1)
        }
        return 8
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    grid
                    GeometryReader { geometry in
                        lane(width: geometry.size.width - gutter)
                            .offset(x: gutter)
                    }
                }
                .frame(height: hourHeight * 24)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                if loading {
                    ProgressView()
                        .padding(.top, 24)
                        .accessibilityLabel("Loading your events")
                }
            }
            .onAppear { proxy.scrollTo(target, anchor: .top) }
            .onChange(of: day) {
                if reduceMotion {
                    proxy.scrollTo(target, anchor: .top)
                } else {
                    withAnimation(Motion.gentle) { proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
    }

    private var grid: some View {
        TimelineView(.everyMinute) { context in
            let now = calendar.isDateInToday(day) ? Int(context.date.timeIntervalSince(calendar.startOfDay(for: day)) / 60) : -100
            hours(hiding: now)
        }
    }

    private func hours(hiding now: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(CalendarMath.clock(hour * 60))
                        .font(QuietGPTFont.monoSmall)
                        .foregroundStyle(palette.text3)
                        .opacity(abs(hour * 60 - now) < 15 ? 0 : 1)
                        .frame(width: gutter - 8, alignment: .leading)
                        .offset(y: -7)
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .accessibilityHidden(true)
    }

    private func y(_ minutes: Int) -> CGFloat {
        CGFloat(minutes) / 60 * hourHeight
    }

    private func lane(width: CGFloat) -> some View {
        let start = calendar.startOfDay(for: day)
        let placed = CalendarMath.placed(CalendarMath.timed(items, on: day, calendar: calendar))
        return ZStack(alignment: .topLeading) {
            ForEach(CalendarMath.free(items, on: day, calendar: calendar), id: \.lowerBound) { slot in
                FreeBlock(slot: slot)
                    .frame(width: width, height: max(y(slot.upperBound - slot.lowerBound) - 4, 20))
                    .offset(y: y(slot.lowerBound) + 2)
            }
            ForEach(placed, id: \.item.id) { entry in
                let from = max(0, Int(entry.item.start.timeIntervalSince(start) / 60))
                let to = min(24 * 60, Int(entry.item.end.timeIntervalSince(start) / 60))
                let column = (width - CGFloat(entry.columns - 1) * 3) / CGFloat(entry.columns)
                EventBlock(item: entry.item, from: from, to: to, height: max(y(to - from) - 2, 26)) { open(entry.item) }
                    .frame(width: column)
                    .offset(x: CGFloat(entry.column) * (column + 3), y: y(from) + 1)
            }
            if calendar.isDateInToday(day) {
                TimelineView(.everyMinute) { context in
                    let minutes = Int(context.date.timeIntervalSince(start) / 60)
                    NowLine(minutes: minutes, width: width, gutter: gutter)
                        .offset(x: -gutter, y: y(minutes) - 5)
                }
            }
        }
        .id(day)
        .transition(.opacity)
        .animation(reduceMotion ? nil : Motion.gentle, value: day)
    }
}

private struct FreeBlock: View {
    let slot: ClosedRange<Int>

    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let ramp = AsciiGlyphs.ramp
                let cell = CGSize(width: 5.4, height: 11)
                let rows = Int(size.height / cell.height) + 1
                let columns = Int(size.width / cell.width) + 1
                let phase = Double(slot.lowerBound) * 0.37
                for row in 0..<rows {
                    var line = ""
                    for column in 0..<columns {
                        let x = Double(column)
                        let y = Double(row)
                        let wave = sin(x * 0.11 + phase) + sin(y * 0.23 - x * 0.05 + phase * 1.7) + 0.6 * sin((x + y * 2) * 0.07)
                        let seed = (row &* 73_856_093) ^ (column &* 19_349_663) ^ (slot.lowerBound &* 83_492_791)
                        let grain = Double(abs(seed) % 100) / 100
                        let level = max(0, (wave + 2.6) / 5.2 * 0.55 + grain * 0.25 - 0.35)
                        line.append(ramp[min(2, Int(level * 8))])
                    }
                    context.draw(Text(line).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.text3.opacity(0.55)), at: CGPoint(x: 0, y: CGFloat(row) * cell.height), anchor: .topLeading)
                }
            }
            Text("Free \(CalendarMath.clock(slot.lowerBound)) to \(CalendarMath.clock(slot.upperBound))")
                .font(QuietGPTFont.footnote)
                .foregroundStyle(palette.text2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(palette.surface, in: .rect(cornerRadius: 6, style: .continuous))
                .padding(6)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 4])) }
        .accessibilityElement(children: .combine)
    }
}

private struct EventBlock: View {
    let item: CalendarItem
    let from: Int
    let to: Int
    let height: CGFloat
    let action: () -> Void

    @Environment(\.palette) private var palette

    private var title: String {
        item.title.isEmpty ? String(localized: "No title") : item.title
    }

    private var time: String {
        String(localized: "\(CalendarMath.clock(from)) to \(CalendarMath.clock(to))")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(QuietGPTFont.callout)
                    .foregroundStyle(palette.text)
                    .lineLimit(height >= 64 ? 2 : 1)
                if height >= 44 {
                    Text(time)
                        .font(QuietGPTFont.monoSmall)
                        .foregroundStyle(palette.text2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, height >= 44 ? 6 : 3)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .background(palette.raised, in: .rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.field, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityLabel("\(title), \(time)")
    }
}

private struct NowLine: View {
    let minutes: Int
    let width: CGFloat
    let gutter: CGFloat

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            Text(CalendarMath.clock(minutes))
                .font(QuietGPTFont.monoSmall.weight(.semibold))
                .foregroundStyle(palette.now)
                .frame(width: gutter - 6, alignment: .leading)
                .background(palette.background)
            Circle()
                .fill(palette.now)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(palette.now)
                .frame(width: width, height: 2)
        }
        .frame(height: 10)
        .allowsHitTesting(false)
        .accessibilityLabel(String(localized: "Now, \(CalendarMath.clock(minutes))"))
    }
}

private struct CalendarAccessView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let action: LocalizedStringKey
    let run: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Calendar")
                .font(QuietGPTFont.largeTitle)
                .foregroundStyle(palette.text)
                .padding(.top, 24)
                .accessibilityAddTraits(.isHeader)
            LiquidField(mode: .drift, mask: .vignette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, -20)
            Text(title)
                .font(QuietGPTFont.lead)
                .foregroundStyle(palette.text)
            Text(message)
                .font(QuietGPTFont.subheadline)
                .foregroundStyle(palette.text2)
                .padding(.top, 8)
            Button(action: run) {
                Text(action)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
