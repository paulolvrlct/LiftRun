import SwiftUI
import SwiftData

// MARK: - Écran principal Nutrition (Premium)

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var premium = PremiumStore.shared

    @AppStorage("nutritionGoal") private var goalRaw = NutritionGoal.maintain.rawValue
    @AppStorage("profileWeightKg") private var weightKg = 70.0
    @AppStorage("profileHeightCm") private var heightCm = 175
    @AppStorage("profileAge") private var age = 25
    @AppStorage("profileSex") private var sexRaw = UserSex.unspecified.rawValue

    @Query(sort: \FoodEntry.date) private var allEntries: [FoodEntry]
    @Query private var sessions: [WorkoutSession]
    @Query private var runs: [RunSession]

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var showAddFood = false
    @State private var showPaywall = false

    private var calendar: Calendar { Calendar.current }
    private var goal: NutritionGoal { NutritionGoal(rawValue: goalRaw) ?? .maintain }
    private var sex: UserSex { UserSex(rawValue: sexRaw) ?? .unspecified }

    private var plan: NutritionPlan {
        NutritionPlanner.plan(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex,
                              weeklyActivities: NutritionPlanner.weeklyActivities(context: context),
                              goal: goal)
    }

    private var dayEntries: [FoodEntry] {
        allEntries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }
    private var consumedKcal: Double { dayEntries.reduce(0) { $0 + $1.kcal } }

    private var burnedKcal: Int {
        let workout = sessions
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + CalorieEstimator.workoutKcal(durationSeconds: $1.durationSeconds, weightKg: weightKg) }
        let running = runs
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + CalorieEstimator.runKcal(distanceKm: $1.distanceKm, weightKg: weightKg) }
        return workout + running
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if premium.isPremium {
                    dayPicker
                    summaryCard
                    mealsSection
                    disclaimer
                } else {
                    lockedCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if premium.isPremium {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddFood = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddFood) {
            AddFoodView(day: day)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: Verrou Premium

    private var lockedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Coach nutrition")
                .font(.title3.weight(.semibold))
            Text("Objectif calories et macros selon ton régime (sèche, maintien, prise de masse), journal alimentaire sur la base CIQUAL de l'ANSES, calories brûlées par tes séances et tes courses.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showPaywall = true
            } label: {
                Label("Débloquer avec Premium", systemImage: "crown.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .padding(.top, 40)
    }

    // MARK: Navigation par jour

    private var dayPicker: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(calendar.isDateInToday(day) ? "Aujourd'hui"
                 : calendar.isDateInYesterday(day) ? "Hier"
                 : day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headline)
            Spacer()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .disabled(calendar.isDateInToday(day))
        }
        .padding(.horizontal, 8)
    }

    private func shiftDay(_ delta: Int) {
        if let d = calendar.date(byAdding: .day, value: delta, to: day), d <= .now {
            day = d
        }
    }

    // MARK: Carte résumé (anneau + objectif + macros + détails)

    private var summaryCard: some View {
        VStack(spacing: 16) {
            CalorieRing(consumed: consumedKcal, target: plan.targetKcal)
                .frame(width: 150, height: 150)

            // objectif : un menu compact plutôt qu'un gros sélecteur
            Menu {
                ForEach(NutritionGoal.allCases) { g in
                    Button {
                        goalRaw = g.rawValue
                    } label: {
                        Label(g.rawValue, systemImage: g.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: goal.icon)
                    Text("Objectif : \(goal.rawValue)")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.indigo.opacity(0.12), in: Capsule())
                .foregroundStyle(.indigo)
            }

            VStack(spacing: 10) {
                macroBar("Protéines", consumed: dayEntries.reduce(0) { $0 + $1.protein },
                         target: plan.proteinG, color: .red)
                macroBar("Glucides", consumed: dayEntries.reduce(0) { $0 + $1.carbs },
                         target: plan.carbsG, color: .orange)
                macroBar("Lipides", consumed: dayEntries.reduce(0) { $0 + $1.fat },
                         target: plan.fatG, color: .yellow)
            }

            DisclosureGroup {
                VStack(spacing: 6) {
                    detailRow("Métabolisme de base", "\(Int(plan.bmr)) kcal")
                    detailRow("Dépense estimée (activité mesurée)", "\(Int(plan.tdee)) kcal")
                    detailRow("Brûlées par le sport ce jour", "\(burnedKcal) kcal")
                    detailRow(goal.rawValue, goal.blurb)
                }
                .padding(.top, 6)
            } label: {
                Text("Détails du calcul")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }

    private func macroBar(_ label: String, consumed: Double, target: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text("\(Int(consumed)) / \(Int(target)) g")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(consumed, target), total: max(target, 1))
                .tint(color)
        }
    }

    // MARK: Journal

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dayEntries.isEmpty {
                Button {
                    showAddFood = true
                } label: {
                    Label("Ajouter mon premier aliment", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            } else {
                ForEach(MealKind.allCases) { meal in
                    let entries = dayEntries.filter { $0.meal == meal.rawValue }
                    if !entries.isEmpty {
                        mealCard(meal, entries: entries)
                    }
                }
                Button {
                    showAddFood = true
                } label: {
                    Label("Ajouter un aliment", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
        }
    }

    private func mealCard(_ meal: MealKind, entries: [FoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(meal.rawValue, systemImage: meal.icon)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(entries.reduce(0) { $0 + $1.kcal })) kcal")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Text((FoodCategory(rawValue: entry.category) ?? .misc).emoji)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.footnote)
                            .lineLimit(1)
                        Text("\(Int(entry.grams)) \(entry.category == FoodCategory.drinks.rawValue ? "mL" : "g")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(entry.kcal)) kcal")
                        .font(.caption.monospacedDigit())
                }
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(entry)
                        try? context.save()
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private var disclaimer: some View {
        Text("Estimations indicatives calculées à partir de ton profil. Elles ne remplacent pas l'avis d'un professionnel de santé ou de nutrition.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

// MARK: - Anneau calories

struct CalorieRing: View {
    let consumed: Double
    let target: Double
    var lineWidth: CGFloat = 14
    var showText = true

    private var progress: Double { min(consumed / max(target, 1), 1) }
    private var over: Bool { consumed > target }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    over ? AnyShapeStyle(Color.orange)
                         : AnyShapeStyle(AngularGradient(colors: [.indigo, .purple, .indigo],
                                                         center: .center)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            if showText {
                VStack(spacing: 2) {
                    Text("\(Int(consumed))")
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    Text("/ \(Int(target)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if over {
                        Text("objectif dépassé")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

// MARK: - Ajout d'un aliment (recherche CIQUAL par catégorie)

struct AddFoodView: View {
    let day: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedCategory: FoodCategory?
    @State private var selected: CiqualFood?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // puces de catégories avec logos
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FoodCategory.allCases) { category in
                            let isOn = selectedCategory == category
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedCategory = isOn ? nil : category
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(category.emoji)
                                    Text(category.name)
                                        .font(.footnote.weight(.medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isOn ? Color.indigo : Color(.tertiarySystemFill),
                                            in: Capsule())
                                .foregroundStyle(isOn ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                List(FoodCatalog.search(query, category: selectedCategory)) { food in
                    Button {
                        selected = food
                    } label: {
                        HStack(spacing: 10) {
                            Text(food.category.emoji)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text("P \(Int(food.p)) · G \(Int(food.c)) · L \(Int(food.f)) pour 100 g")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(food.k)) kcal")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $query, prompt: "Rechercher un aliment")
            .navigationTitle("Ajouter un aliment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(item: $selected) { food in
                FoodQuantityView(food: food, day: day) {
                    dismiss()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - Quantité et repas

struct FoodQuantityView: View {
    let food: CiqualFood
    let day: Date
    var onAdded: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var grams: Double = 100
    @State private var mealRaw = MealKind.lunch.rawValue

    private var kcal: Int { Int(food.k * grams / 100) }
    /// Boissons affichées en volume (1 mL ≈ 1 g pour les liquides)
    private var unit: String { food.category == .drinks ? "mL" : "g" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(food.name).font(.subheadline.weight(.semibold))
                    } icon: {
                        Text(food.category.emoji)
                    }
                }
                Section("Quantité") {
                    Stepper("\(Int(grams)) \(unit)", value: $grams, in: 5...1500, step: 5)
                    Slider(value: $grams, in: 5...500, step: 5)
                    LabeledContent("Apport", value: "\(kcal) kcal")
                }
                Section("Repas") {
                    Picker("Repas", selection: $mealRaw) {
                        ForEach(MealKind.allCases) { meal in
                            Label(meal.rawValue, systemImage: meal.icon).tag(meal.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Button {
                        add()
                    } label: {
                        Text("Ajouter au journal")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Quantité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func add() {
        // horodate dans la journée affichée (midi pour les jours passés)
        let date = Calendar.current.isDateInToday(day) ? Date.now
            : Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? day
        let entry = FoodEntry(date: date, name: food.name, grams: grams,
                              kcalPer100: food.k, proteinPer100: food.p,
                              carbsPer100: food.c, fatPer100: food.f,
                              meal: mealRaw, category: food.g)
        context.insert(entry)
        try? context.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
        onAdded()
    }
}

// MARK: - Carte Nutrition de l'accueil

struct NutritionHomeCard: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var premium = PremiumStore.shared

    @AppStorage("nutritionGoal") private var goalRaw = NutritionGoal.maintain.rawValue
    @AppStorage("profileWeightKg") private var weightKg = 70.0
    @AppStorage("profileHeightCm") private var heightCm = 175
    @AppStorage("profileAge") private var age = 25
    @AppStorage("profileSex") private var sexRaw = UserSex.unspecified.rawValue

    @Query private var allEntries: [FoodEntry]

    private var consumedToday: Double {
        allEntries
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.kcal }
    }

    private var targetKcal: Double {
        NutritionPlanner.plan(weightKg: weightKg, heightCm: heightCm, age: age,
                              sex: UserSex(rawValue: sexRaw) ?? .unspecified,
                              weeklyActivities: NutritionPlanner.weeklyActivities(context: context),
                              goal: NutritionGoal(rawValue: goalRaw) ?? .maintain).targetKcal
    }

    var body: some View {
        HStack(spacing: 14) {
            if premium.isPremium {
                CalorieRing(consumed: consumedToday, target: targetKcal,
                            lineWidth: 6, showText: false)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nutrition").font(.headline).foregroundStyle(.primary)
                    Text("\(Int(consumedToday)) / \(Int(targetKcal)) kcal aujourd'hui")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(LinearGradient(colors: [.orange, .red],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach nutrition").font(.headline).foregroundStyle(.primary)
                    Label("Premium", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
