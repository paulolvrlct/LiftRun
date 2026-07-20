import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \RunSession.date, order: .reverse) private var runs: [RunSession]
    @Query(sort: \Supplement.order) private var supplements: [Supplement]
    @Query private var intakes: [SupplementIntake]

    @State private var displayedMonth = Date.now
    @State private var selectedDay: Date? = nil

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    calendarGrid
                    activityList
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendrier")
        }
    }

    // MARK: En-tête mois

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()).capitalized)
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 8)
    }

    private func shiftMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = d
            selectedDay = nil
        }
    }

    // MARK: Grille calendrier

    private var calendarGrid: some View {
        let days = makeDays()
        let symbols = ["L", "M", "M", "J", "V", "S", "D"]

        return VStack(spacing: 8) {
            HStack {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private func dayCell(_ day: Date) -> some View {
        let hasSession = sessions.contains { calendar.isDate($0.date, inSameDayAs: day) }
        let hasRun = runs.contains { calendar.isDate($0.date, inSameDayAs: day) }
        let hasSupplements = SupplementTracker.isComplete(day: day, supplements: supplements,
                                                          intakes: intakes)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.monospacedDigit())
                    .fontWeight(isToday ? .bold : .regular)
                HStack(spacing: 3) {
                    if hasSession {
                        Circle().fill(Color.indigo).frame(width: 5, height: 5)
                    }
                    if hasRun {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                    }
                    if hasSupplements {
                        Circle().fill(Color.pink).frame(width: 5, height: 5)
                    }
                    if !hasSession && !hasRun && !hasSupplements {
                        Circle().fill(.clear).frame(width: 5, height: 5)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                isSelected ? Color.indigo.opacity(0.18)
                : isToday ? Color(.tertiarySystemFill)
                : .clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .foregroundStyle(isSelected ? .indigo : .primary)
        }
        .buttonStyle(.plain)
    }

    /// Jours du mois affiché, avec des nil pour caler le 1er sur le bon jour de semaine (lundi en premier)
    private func makeDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstDay = interval.start
        let weekday = calendar.component(.weekday, from: firstDay) // 1 = dimanche
        let leading = (weekday + 5) % 7 // décalage pour commencer lundi
        let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        return days
    }

    // MARK: Liste des activités (séances + courses)

    private enum ActivityEntry: Identifiable {
        case workout(WorkoutSession)
        case run(RunSession)

        var id: PersistentIdentifier {
            switch self {
            case .workout(let s): s.persistentModelID
            case .run(let r): r.persistentModelID
            }
        }

        var date: Date {
            switch self {
            case .workout(let s): s.date
            case .run(let r): r.date
            }
        }
    }

    private func isVisible(_ date: Date) -> Bool {
        if let selectedDay {
            return calendar.isDate(date, inSameDayAs: selectedDay)
        }
        return calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
    }

    private var filteredEntries: [ActivityEntry] {
        let workouts = sessions.filter { isVisible($0.date) }.map(ActivityEntry.workout)
        let running = runs.filter { isVisible($0.date) }.map(ActivityEntry.run)
        return (workouts + running).sorted { $0.date > $1.date }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDay == nil ? "Ce mois-ci" : "Activités du jour")
                .font(.headline)
                .padding(.leading, 4)

            if filteredEntries.isEmpty {
                ContentUnavailableView("Aucune activité", systemImage: "moon.zzz",
                                       description: Text("Repos... ou jour de skip ? 👀"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                ForEach(filteredEntries) { entry in
                    switch entry {
                    case .workout(let session):
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                context.delete(session)
                                try? context.save()
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    case .run(let run):
                        NavigationLink {
                            RunDetailView(run: run)
                        } label: {
                            RunRow(run: run)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                context.delete(run)
                                try? context.save()
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Détail d'une séance passée

struct SessionDetailView: View {
    let session: WorkoutSession

    /// Séries groupées par exercice, dans l'ordre des séries
    private var exercises: [(name: String, sets: [SetRecord])] {
        Dictionary(grouping: session.sets, by: \.exerciseName)
            .map { (name: $0.key, sets: $0.value.sorted { $0.setIndex < $1.setIndex }) }
            .sorted { $0.name < $1.name }
    }

    private var burnedKcal: Int {
        let stored = UserDefaults.standard.double(forKey: "profileWeightKg")
        return CalorieEstimator.workoutKcal(durationSeconds: session.durationSeconds,
                                            weightKg: stored > 0 ? stored : 70)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    detailTile(PaceFormatter.duration(session.durationSeconds), "durée")
                    detailTile("\(session.sets.count)", "séries")
                    detailTile(session.totalVolume >= 1000
                               ? String(format: "%.1f t", session.totalVolume / 1000)
                               : "\(Int(session.totalVolume)) kg", "volume")
                    detailTile("\(burnedKcal)", "kcal")
                }

                ForEach(exercises, id: \.name) { exercise in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(exercise.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(exercise.sets.count) série\(exercise.sets.count > 1 ? "s" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(exercise.sets) { set in
                            HStack {
                                Text("Série \(set.setIndex)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(set.weight > 0
                                     ? "\(set.reps) × \(set.weight.clean) kg"
                                     : "\(set.reps) reps")
                                    .font(.footnote.monospacedDigit().weight(.medium))
                            }
                        }
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.templateName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Ligne course

private struct RunRow: View {
    let run: RunSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "Course · %.2f km", run.distanceKm))
                    .font(.subheadline.weight(.semibold))
                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(PaceFormatter.string(secPerKm: run.averagePaceSecPerKm))
                    .font(.caption.monospacedDigit())
                Text(PaceFormatter.duration(run.durationSeconds))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Ligne séance

private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.templateName).font(.subheadline.weight(.semibold))
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.sets.count) séries")
                    .font(.caption.monospacedDigit())
                Text("\(Int(session.totalVolume)) kg volume")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}
