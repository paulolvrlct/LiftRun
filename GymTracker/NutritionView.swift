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
                    .accessibilityLabel("Ajouter un aliment")
                }
            }
        }
        .sheet(isPresented: $showAddFood) {
            AddFoodView(day: day)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear { NutritionPlanner.publishForWidget(context: context) }
        .onChange(of: goalRaw) { NutritionPlanner.publishForWidget(context: context) }
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
            .tint(Color.brand)
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
                .background(Color.brand.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.brand)
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
                .tint(Color.brand)
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
                .tint(Color.brand)
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
                        // retire aussi les échantillons Apple Santé liés
                        let ids = entry.healthIDs.split(separator: ",").map(String.init)
                        if !ids.isEmpty {
                            Task { await HealthKitManager.shared.deleteFoodSamples(ids: ids) }
                        }
                        context.delete(entry)
                        context.saveLogging()
                        NutritionPlanner.publishForWidget(context: context)
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
                         : AnyShapeStyle(AngularGradient(colors: [Color.brand, .purple, Color.brand],
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

    @Query(sort: \FoodEntry.date, order: .reverse) private var history: [FoodEntry]

    enum Source: String, CaseIterable, Identifiable {
        case recent = "Récents"
        case common = "Courants"
        case all = "Tout"
        var id: String { rawValue }
    }

    @State private var source: Source = .recent
    @State private var query = ""
    @State private var selectedCategory: FoodCategory?
    @State private var selected: CiqualFood?
    @State private var showScanner = false
    // produit scanné, appliqué à la fermeture de la feuille de scan
    @State private var scannedProduct: ScannedProduct?
    // poids net du paquet du produit sélectionné (scan uniquement)
    @State private var selectedPackageGrams: Double?

    /// Derniers aliments consommés, sans doublon, du plus récent au plus ancien
    private var recents: [CiqualFood] {
        var seen = Set<String>()
        var out: [CiqualFood] = []
        for entry in history where !seen.contains(entry.name.lowercased()) {
            seen.insert(entry.name.lowercased())
            out.append(CiqualFood(n: entry.name, g: entry.category,
                                  k: entry.kcalPer100, p: entry.proteinPer100,
                                  c: entry.carbsPer100, f: entry.fatPer100))
            if out.count >= 40 { break }
        }
        return out
    }

    private var results: [CiqualFood] {
        switch source {
        case .recent:
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            var out = recents
            if let selectedCategory { out = out.filter { $0.g == selectedCategory.rawValue } }
            if !trimmed.isEmpty { out = out.filter { $0.n.localizedStandardContains(trimmed) } }
            return out
        case .common:
            return FoodCatalog.search(query, category: selectedCategory, deepCatalog: false)
        case .all:
            return FoodCatalog.search(query, category: selectedCategory)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

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
                                .background(isOn ? Color.brand : Color(.tertiarySystemFill),
                                            in: Capsule())
                                .foregroundStyle(isOn ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if results.isEmpty {
                    ContentUnavailableView(
                        source == .recent ? "Aucun aliment récent" : "Aucun résultat",
                        systemImage: source == .recent ? "clock.arrow.circlepath" : "magnifyingglass",
                        description: Text(source == .recent
                            ? "Tes aliments déjà consommés apparaîtront ici pour un ajout en un tap."
                            : "Essaie « Tout » pour chercher dans la table complète.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(results) { food in
                        Button {
                            selectedPackageGrams = nil   // aliment générique : pas de paquet
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
            }
            .searchable(text: $query, prompt: "Rechercher un aliment")
            .navigationTitle("Ajouter un aliment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scanner un code-barres")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            // la feuille de quantité s'ouvre une fois le scanner refermé
            .sheet(isPresented: $showScanner, onDismiss: {
                if let scannedProduct {
                    selectedPackageGrams = scannedProduct.packageGrams
                    selected = scannedProduct.food
                    self.scannedProduct = nil
                }
            }) {
                FoodScanSheet { product in scannedProduct = product }
            }
            .onAppear {
                // pas d'historique : on démarre sur les aliments courants
                if recents.isEmpty { source = .common }
            }
            .sheet(item: $selected) { food in
                FoodQuantityView(food: food, day: day, packageGrams: selectedPackageGrams) {
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
    /// Poids net du paquet (produit scanné) : active la part consommée
    var packageGrams: Double? = nil
    var onAdded: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var grams: Double = 100
    @FocusState private var gramsFocused: Bool

    /// Parts rapides proposées pour un produit emballé
    static let portionFractions: [(label: String, value: Double)] =
        [("¼", 0.25), ("⅓", 1.0 / 3), ("½", 0.5), ("¾", 0.75), ("Tout", 1.0)]
    // présélection du repas selon l'heure (petit-déj / déjeuner / goûter / dîner)
    @State private var mealRaw = MealKind.current.rawValue

    private var kcal: Int { Int(food.k * grams / 100) }
    /// Boissons affichées en volume (1 mL ≈ 1 g pour les liquides)
    private var unit: String { food.category == .drinks ? "mL" : "g" }

    /// Portions rapides adaptées à l'aliment (un tap au lieu de compter les grammes)
    private var portions: [(label: String, grams: Double)] {
        let name = food.n.lowercased()
        // compléments : la dose type prime sur la portion de la catégorie
        if name.contains("créatine") && !name.contains("shaker") {
            return [("1 dose · 5 g", 5), ("2 doses · 10 g", 10)]
        }
        if name.contains("bcaa") || name.contains("glutamine") {
            return [("1 dose · 10 g", 10), ("2 doses · 20 g", 20)]
        }
        if name.contains("pre-workout") {
            return [("1 dose · 15 g", 15)]
        }
        if name.contains("maltodextrine") {
            return [("1 dose · 30 g", 30), ("2 doses · 60 g", 60)]
        }
        if name.contains("gel énergétique") {
            return [("1 gel · 30 g", 30), ("2 gels · 60 g", 60)]
        }
        if name.contains("barre") {
            return [("1 barre · 40 g", 40), ("1 grosse barre · 60 g", 60)]
        }
        if name.contains("whey") || name.contains("protéine végétale") {
            return [("1 dose · 30 g", 30), ("2 doses · 60 g", 60), ("3 doses · 90 g", 90)]
        }
        switch food.category {
        case .drinks:
            return [("Verre · 250 mL", 250), ("Canette · 330 mL", 330), ("Bouteille · 500 mL", 500)]
        case .fruitsVeg:
            return [("1 moyen · 150 g", 150), ("Portion · 200 g", 200)]
        case .cereals:
            return [("Portion · 150 g", 150), ("Grosse portion · 250 g", 250)]
        case .meatFish:
            return [("Portion · 120 g", 120), ("Grosse portion · 180 g", 180)]
        case .dairy:
            return [("Yaourt · 125 g", 125), ("Portion fromage · 30 g", 30)]
        case .sweets:
            return [("Portion · 50 g", 50), ("Part · 100 g", 100)]
        case .fats:
            return [("Cuillère · 10 g", 10), ("Noix · 15 g", 15)]
        case .dishes:
            return [("Petite assiette · 200 g", 200), ("Assiette · 300 g", 300)]
        case .misc:
            return [("Cuillère · 10 g", 10), ("Portion · 100 g", 100)]
        }
    }

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
                // Produit scanné dont on connaît le poids : on raisonne en parts
                if let pack = packageGrams, pack > 0 {
                    Section("Part du produit") {
                        HStack {
                            Text("Paquet : \(Int(pack)) \(unit)")
                                .font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((grams / pack * 100).rounded())) %")
                                .font(.footnote.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.brand)
                        }
                        Slider(value: Binding(
                            get: { min(max(grams / pack, 0), 1) },
                            set: { grams = max(1, ($0 * pack).rounded()) }
                        ), in: 0...1)
                        .accessibilityLabel("Part du paquet consommée")

                        HStack(spacing: 8) {
                            ForEach(Self.portionFractions, id: \.label) { portion in
                                let isOn = abs(grams - pack * portion.value) < 1
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        grams = max(1, (pack * portion.value).rounded())
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text(portion.label)
                                        .font(.footnote.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(isOn ? Color.brand : Color(.tertiarySystemFill),
                                                    in: Capsule())
                                        .foregroundStyle(isOn ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Quantité") {
                    // portions en un tap (« 1 verre de coca », « 1 dose de whey »…)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(portions, id: \.grams) { portion in
                                let isOn = grams == portion.grams
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        grams = portion.grams
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text(portion.label)
                                        .font(.footnote.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(isOn ? Color.brand : Color(.tertiarySystemFill),
                                                    in: Capsule())
                                        .foregroundStyle(isOn ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    // saisie directe au clavier + pas à pas, sur la même plage que le slider
                    HStack {
                        Text("Quantité")
                        Spacer()
                        TextField("100", value: $grams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .focused($gramsFocused)
                            .accessibilityLabel("Quantité en \(unit)")
                        Text(unit).foregroundStyle(.secondary)
                    }
                    Stepper("Ajuster", value: $grams, in: 5...2000, step: 5)
                        .labelsHidden()
                    Slider(value: $grams, in: 5...2000, step: 5)
                        .accessibilityLabel("Quantité")
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
                    .tint(Color.brand)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Quantité")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // petit conditionnement (yaourt, barre, canette) : on part du paquet entier
                if let pack = packageGrams, pack > 0, pack <= 400 {
                    grams = pack.rounded()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { gramsFocused = false }
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
        context.saveLogging()
        NutritionPlanner.publishForWidget(context: context)

        // Écrit aussi dans Apple Santé et mémorise les UUID pour la suppression
        Task {
            let ids = await HealthKitManager.shared.saveFood(
                kcal: entry.kcal, protein: entry.protein,
                carbs: entry.carbs, fat: entry.fat,
                date: entry.date, name: entry.name)
            if !ids.isEmpty {
                entry.healthIDs = ids.joined(separator: ",")
                context.saveLogging()
            }
        }

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
