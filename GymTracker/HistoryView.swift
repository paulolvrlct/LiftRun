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
                    monthSummary
                    calendarGrid
                    activityList
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendrier")
        }
    }

    // MARK: Résumé du mois (série, jours actifs, séances, km)

    private func inMonth(_ d: Date) -> Bool {
        calendar.isDate(d, equalTo: displayedMonth, toGranularity: .month)
    }

    /// Nombre de semaines consécutives (jusqu'à aujourd'hui) avec au moins une séance.
    /// La semaine en cours, si elle n'a pas encore de séance, n'interrompt pas la série.
    private var weekStreak: Int {
        var count = 0
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        var isCurrentWeek = true
        while true {
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            let hasSession = sessions.contains { $0.date >= cursor && $0.date < weekEnd }
            if hasSession {
                count += 1
            } else if !isCurrentWeek {
                break
            }
            isCurrentWeek = false
            guard let prev = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    private var monthSessions: Int { sessions.filter { inMonth($0.date) }.count }

    private var monthKm: Double {
        runs.filter { inMonth($0.date) }.reduce(0) { $0 + $1.distanceKm }
    }

    private var monthActiveDays: Int {
        let days = (sessions.map(\.date) + runs.map(\.date))
            .filter { inMonth($0) }
            .map { calendar.startOfDay(for: $0) }
        return Set(days).count
    }

    private var monthSummary: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            summaryTile(icon: "flame.fill", tint: .orange, value: "\(weekStreak)",
                        label: weekStreak > 1 ? "semaines de suite" : "semaine de suite")
            summaryTile(icon: "calendar.badge.checkmark", tint: Color.brand, value: "\(monthActiveDays)",
                        label: "jours actifs")
            summaryTile(icon: "dumbbell.fill", tint: Color.brand, value: "\(monthSessions)",
                        label: monthSessions > 1 ? "séances" : "séance")
            summaryTile(icon: "figure.run", tint: .green,
                        value: monthKm >= 10 ? String(format: "%.0f", monthKm) : monthKm.clean,
                        label: "km courus")
        }
    }

    private func summaryTile(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.weight(.semibold).monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    // MARK: En-tête mois

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Mois précédent")
            Spacer()
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()).capitalized)
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Mois suivant")
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 5) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            legend
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(Color.brand, "Muscu")
            legendItem(.green, "Course")
            legendItem(.pink, "Compléments")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 11, height: 11)
            Text(label)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let hasSession = sessions.contains { calendar.isDate($0.date, inSameDayAs: day) }
        let hasRun = runs.contains { calendar.isDate($0.date, inSameDayAs: day) }
        let hasSupplements = SupplementTracker.isComplete(day: day, supplements: supplements,
                                                          intakes: intakes)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        // couleur pleine : muscu > course > compléments seuls
        let solid = hasSession || hasRun
        let fill: Color = hasSession ? Color.brand
            : hasRun ? .green
            : hasSupplements ? Color.pink.opacity(0.16)
            : .clear
        let fg: Color = solid ? .white : (hasSupplements ? .pink : .primary)

        // anneau : sélection prioritaire, sinon jour du jour
        let ringColor: Color
        if isSelected { ringColor = solid ? .white : Color.brand }
        else if isToday { ringColor = solid ? .white.opacity(0.85) : Color.brand }
        else { ringColor = .clear }
        let ringWidth: CGFloat = (isSelected || isToday) ? 2 : 0

        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.monospacedDigit())
                    .fontWeight(solid || isToday ? .semibold : .regular)
                HStack(spacing: 2) {
                    // séance + course le même jour → deux points ; compléments en plus → point rose
                    if hasSession && hasRun {
                        Circle().fill(.white).frame(width: 3.5, height: 3.5)
                        Circle().fill(.green).frame(width: 3.5, height: 3.5)
                    }
                    if hasSupplements && solid {
                        Circle().fill(.pink).frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .foregroundStyle(fg)
            .background(fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(ringColor, lineWidth: ringWidth)
            )
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
                                context.saveLogging()
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
                                context.saveLogging()
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
                .foregroundStyle(Color.brand)

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
