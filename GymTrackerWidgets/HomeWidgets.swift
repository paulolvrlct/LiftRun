import WidgetKit
import SwiftUI
import SwiftData
import Charts

// MARK: - Widget Streak (jauge de jours consécutifs)

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let weekActivities: Int
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 3, weekActivities: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        // Rafraîchit au changement de jour (le streak ne bouge pas plus vite)
        let nextMidnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        completion(Timeline(entries: [loadEntry()], policy: .after(nextMidnight)))
    }

    /// Lit la base SwiftData partagée (App Group) — même calcul que HomeView.
    private func loadEntry() -> StreakEntry {
        guard let container = try? SharedStore.makeContainer() else {
            return StreakEntry(date: .now, streak: 0, weekActivities: 0)
        }
        let context = ModelContext(container)
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let runs = (try? context.fetch(FetchDescriptor<RunSession>())) ?? []
        let calendar = Calendar.current

        let days = Set((sessions.map(\.date) + runs.map(\.date)).map { calendar.startOfDay(for: $0) })
        var streak = 0
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }

        let week = sessions.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count
            + runs.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count

        return StreakEntry(date: .now, streak: streak, weekActivities: week)
    }
}

struct StreakWidgetView: View {
    let entry: StreakEntry

    var body: some View {
        VStack(spacing: 8) {
            Gauge(value: min(Double(entry.streak), 7), in: 0...7) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(entry.streak)")
                    .font(.title3.bold())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.orange)

            Text(entry.streak > 0 ? "jour\(entry.streak > 1 ? "s" : "") d'affilée" : "streak à lancer")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(entry.weekActivities) activité\(entry.weekActivities > 1 ? "s" : "") cette semaine")
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakWidget", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Tes jours d'activité consécutifs (muscu + course).")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Widget courbe de volume (Swift Charts)

struct VolumeWeek: Hashable {
    let start: Date
    let volume: Double
}

struct VolumeEntry: TimelineEntry {
    let date: Date
    let weeks: [VolumeWeek]
}

struct VolumeProvider: TimelineProvider {
    func placeholder(in context: Context) -> VolumeEntry {
        let cal = Calendar.current
        let weeks = (0..<6).reversed().map { offset in
            VolumeWeek(start: cal.date(byAdding: .weekOfYear, value: -offset, to: .now)!,
                       volume: Double([1800, 2400, 2100, 2900, 2600, 3200][offset]))
        }
        return VolumeEntry(date: .now, weeks: weeks)
    }

    func getSnapshot(in context: Context, completion: @escaping (VolumeEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VolumeEntry>) -> Void) {
        let nextMidnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        completion(Timeline(entries: [loadEntry()], policy: .after(nextMidnight)))
    }

    /// Volume soulevé (kg) par semaine sur les 6 dernières semaines
    private func loadEntry() -> VolumeEntry {
        let calendar = Calendar.current
        var weeks: [VolumeWeek] = []
        guard let container = try? SharedStore.makeContainer() else {
            return VolumeEntry(date: .now, weeks: [])
        }
        let context = ModelContext(container)
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        for offset in (0..<6).reversed() {
            guard let ref = calendar.date(byAdding: .weekOfYear, value: -offset, to: .now),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: ref) else { continue }
            let volume = sessions
                .filter { interval.contains($0.date) }
                .reduce(0) { $0 + $1.totalVolume }
            weeks.append(VolumeWeek(start: interval.start, volume: volume))
        }
        return VolumeEntry(date: .now, weeks: weeks)
    }
}

struct VolumeChartWidgetView: View {
    let entry: VolumeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.indigo)
                Text("Volume soulevé · 6 semaines")
                    .font(.caption.weight(.semibold))
                Spacer()
            }

            if entry.weeks.allSatisfy({ $0.volume == 0 }) {
                Text("Termine une séance pour voir ta courbe 💪")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(entry.weeks, id: \.start) { week in
                    BarMark(
                        x: .value("Semaine", week.start, unit: .weekOfYear),
                        y: .value("kg", week.volume)
                    )
                    .foregroundStyle(.indigo)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.narrow), centered: true)
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct VolumeChartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VolumeChartWidget", provider: VolumeProvider()) { entry in
            VolumeChartWidgetView(entry: entry)
        }
        .configurationDisplayName("Volume d'entraînement")
        .description("Ton volume soulevé par semaine (Swift Charts).")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget raccourci course

struct RunShortcutEntry: TimelineEntry {
    let date: Date
}

struct RunShortcutProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunShortcutEntry { RunShortcutEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (RunShortcutEntry) -> Void) {
        completion(RunShortcutEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RunShortcutEntry>) -> Void) {
        completion(Timeline(entries: [RunShortcutEntry(date: .now)], policy: .never))
    }
}

struct RunShortcutWidgetView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(
                    LinearGradient(colors: [.green, .teal],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
            Text("Courir")
                .font(.headline)
        }
        // Ouvre l'app directement sur l'onglet Course (géré par RootTabView.onOpenURL)
        .widgetURL(URL(string: "gymtracker://run"))
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct RunShortcutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RunShortcutWidget", provider: RunShortcutProvider()) { _ in
            RunShortcutWidgetView()
        }
        .configurationDisplayName("Démarrer une course")
        .description("Raccourci direct vers le mode course GPS.")
        .supportedFamilies([.systemSmall])
    }
}
