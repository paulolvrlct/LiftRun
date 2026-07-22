import SwiftUI
import SwiftData

// MARK: - Compléments du jour

/// Logique partagée : quels compléments sont pris tel jour, et depuis
/// combien de jours la routine est complète.
enum SupplementTracker {

    static func isTaken(_ supplement: Supplement, on day: Date,
                        intakes: [SupplementIntake]) -> Bool {
        let d = Calendar.current.startOfDay(for: day)
        return intakes.contains { $0.supplementName == supplement.name
            && Calendar.current.isDate($0.date, inSameDayAs: d) }
    }

    /// Jour « complet » : tous les compléments *quotidiens* actifs ont été cochés.
    /// Les optionnels (whey, pre-workout…) n'entrent pas dans la complétude.
    static func isComplete(day: Date, supplements: [Supplement],
                           intakes: [SupplementIntake]) -> Bool {
        let daily = supplements.filter { $0.isActive && $0.isDaily }
        guard !daily.isEmpty else { return false }
        return daily.allSatisfy { isTaken($0, on: day, intakes: intakes) }
    }

    /// Jours consécutifs de routine complète, en tolérant que la journée
    /// en cours ne soit pas encore terminée.
    static func streak(supplements: [Supplement], intakes: [SupplementIntake]) -> Int {
        let calendar = Calendar.current
        guard !supplements.filter(\.isActive).isEmpty else { return 0 }
        var count = 0
        var day = calendar.startOfDay(for: .now)
        if !isComplete(day: day, supplements: supplements, intakes: intakes) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        while isComplete(day: day, supplements: supplements, intakes: intakes) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}

// MARK: - Carte de l'accueil

struct SupplementsCard: View {
    @Query(sort: \Supplement.order) private var supplements: [Supplement]
    @Query private var intakes: [SupplementIntake]

    // seuls les quotidiens comptent dans la progression / la série
    private var daily: [Supplement] { supplements.filter { $0.isActive && $0.isDaily } }
    private var takenCount: Int {
        daily.filter { SupplementTracker.isTaken($0, on: .now, intakes: intakes) }.count
    }
    private var streak: Int {
        SupplementTracker.streak(supplements: supplements, intakes: intakes)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: daily.isEmpty ? 0
                          : Double(takenCount) / Double(daily.count))
                    .stroke(Color.pink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: takenCount)
                Image(systemName: "pills.fill")
                    .font(.footnote)
                    .foregroundStyle(.pink)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Compléments").font(.headline).foregroundStyle(.primary)
                if daily.isEmpty {
                    Text("Choisis ta routine quotidienne")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(takenCount) / \(daily.count) aujourd'hui"
                         + (streak > 0 ? " · \(streak) j d'affilée 🔥" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Écran compléments

struct SupplementsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Supplement.order) private var supplements: [Supplement]
    @Query private var intakes: [SupplementIntake]

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var showPicker = false

    private var calendar: Calendar { Calendar.current }
    private var active: [Supplement] { supplements.filter(\.isActive) }
    // la complétude / série ne concerne que les quotidiens
    private var dailyActive: [Supplement] { active.filter(\.isDaily) }
    private var takenCount: Int {
        dailyActive.filter { SupplementTracker.isTaken($0, on: day, intakes: intakes) }.count
    }
    private var streak: Int {
        SupplementTracker.streak(supplements: supplements, intakes: intakes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dayPicker

                if active.isEmpty {
                    emptyState
                } else {
                    headerCard
                    checklist
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Compléments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPicker = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Ajouter un complément")
            }
        }
        .sheet(isPresented: $showPicker) { SupplementPickerView() }
    }

    private var dayPicker: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Jour précédent")
            Spacer()
            Text(calendar.isDateInToday(day) ? "Aujourd'hui"
                 : calendar.isDateInYesterday(day) ? "Hier"
                 : day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headline)
            Spacer()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .disabled(calendar.isDateInToday(day))
                .accessibilityLabel("Jour suivant")
        }
        .padding(.horizontal, 8)
    }

    private func shiftDay(_ delta: Int) {
        if let d = calendar.date(byAdding: .day, value: delta, to: day), d <= .now { day = d }
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            Text("\(takenCount) / \(dailyActive.count)")
                .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(!dailyActive.isEmpty && takenCount == dailyActive.count
                 ? "Routine complète 💪" : "quotidiens pris")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if streak > 0 {
                Label("\(streak) jour\(streak > 1 ? "s" : "") d'affilée",
                      systemImage: "flame.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, options: .repeating)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private var checklist: some View {
        VStack(spacing: 10) {
            ForEach(active) { supplement in
                let taken = SupplementTracker.isTaken(supplement, on: day, intakes: intakes)
                Button {
                    toggle(supplement, taken: taken)
                } label: {
                    HStack(spacing: 14) {
                        Text(supplement.emoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(supplement.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if !supplement.isDaily {
                                    Text("Optionnel")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                }
                            }
                            if !supplement.dose.isEmpty {
                                Text(supplement.dose)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(taken ? .pink : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        supplement.isDaily.toggle()
                        context.saveLogging()
                    } label: {
                        Label(supplement.isDaily ? "Marquer comme optionnel" : "Marquer comme quotidien",
                              systemImage: supplement.isDaily ? "calendar.badge.minus" : "calendar.badge.checkmark")
                    }
                    Button(role: .destructive) {
                        context.delete(supplement)
                        context.saveLogging()
                    } label: {
                        Label("Retirer de ma routine", systemImage: "trash")
                    }
                }
            }

            Button { showPicker = true } label: {
                Label("Ajouter un complément", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.pink)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pills.fill")
                .font(.system(size: 44))
                .foregroundStyle(.pink)
            Text("Ta routine quotidienne")
                .font(.title3.weight(.semibold))
            Text("Choisis les compléments que tu prends chaque jour : magnésium, créatine, whey, vitamines… Tu les coches en un tap, et ta régularité se suit comme une série.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showPicker = true } label: {
                Label("Composer ma routine", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .padding(.top, 30)
    }

    private func toggle(_ supplement: Supplement, taken: Bool) {
        if taken {
            let d = calendar.startOfDay(for: day)
            for intake in intakes where intake.supplementName == supplement.name
                && calendar.isDate(intake.date, inSameDayAs: d) {
                context.delete(intake)
            }
        } else {
            context.insert(SupplementIntake(date: day, supplementName: supplement.name))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        context.saveLogging()
    }
}

// MARK: - Choix des compléments

struct SupplementPickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Supplement.order) private var supplements: [Supplement]

    @State private var customName = ""
    @State private var customDose = ""
    @State private var customDaily = true

    /// Compléments proposés par défaut (emoji, nom, dose usuelle, quotidien par défaut)
    private let presets: [(emoji: String, name: String, dose: String, daily: Bool)] = [
        ("💪", "Créatine", "5 g", true),
        ("🥛", "Whey", "30 g", false),
        ("🧂", "Magnésium", "300 mg", true),
        ("☀️", "Vitamine D", "1 000 UI", true),
        ("🐟", "Oméga 3", "1 g", true),
        ("💊", "Multivitamines", "1 gélule", true),
        ("🍊", "Vitamine C", "500 mg", true),
        ("🦴", "Zinc", "15 mg", true),
        ("🧬", "BCAA", "10 g", false),
        ("🌿", "Ashwagandha", "600 mg", true),
        ("🩸", "Fer", "14 mg", true),
        ("🦠", "Probiotiques", "1 gélule", true),
        ("⚡", "Pre-workout", "1 dose", false),
        ("💧", "Électrolytes", "1 dose", false),
    ]

    private var existingNames: Set<String> {
        Set(supplements.map { $0.name.lowercased() })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Ajouter") {
                    ForEach(presets, id: \.name) { preset in
                        let already = existingNames.contains(preset.name.lowercased())
                        Button {
                            add(name: preset.name, emoji: preset.emoji, dose: preset.dose,
                                isDaily: preset.daily)
                        } label: {
                            HStack(spacing: 12) {
                                Text(preset.emoji).font(.title3)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(preset.name)
                                            .foregroundStyle(already ? .secondary : .primary)
                                        if !preset.daily {
                                            Text("Optionnel")
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color(.tertiarySystemFill), in: Capsule())
                                        }
                                    }
                                    Text(preset.dose)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: already ? "checkmark" : "plus.circle.fill")
                                    .foregroundStyle(already ? Color.secondary : Color.pink)
                            }
                        }
                        .disabled(already)
                    }
                }

                Section("Autre complément") {
                    TextField("Nom", text: $customName)
                    TextField("Dose (facultatif)", text: $customDose)
                    Toggle("Quotidien", isOn: $customDaily)
                        .tint(.pink)
                    Button("Ajouter") {
                        let name = customName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        add(name: name, emoji: "💊", dose: customDose, isDaily: customDaily)
                        customName = ""; customDose = ""; customDaily = true
                    }
                    .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Mes compléments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    private func add(name: String, emoji: String, dose: String, isDaily: Bool) {
        guard !existingNames.contains(name.lowercased()) else { return }
        context.insert(Supplement(name: name, emoji: emoji, dose: dose,
                                  order: supplements.count, isDaily: isDaily))
        context.saveLogging()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
