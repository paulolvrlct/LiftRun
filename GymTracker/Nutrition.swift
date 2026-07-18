import Foundation
import SwiftData
import WidgetKit

// MARK: - Objectif nutritionnel (Premium)

enum NutritionGoal: String, CaseIterable, Identifiable {
    case cut = "Sèche"
    case maintain = "Maintien"
    case bulk = "Prise de masse"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cut: "arrow.down.right.circle.fill"
        case .maintain: "equal.circle.fill"
        case .bulk: "arrow.up.right.circle.fill"
        }
    }

    /// Multiplicateur appliqué à la dépense totale (TDEE)
    var calorieFactor: Double {
        switch self {
        case .cut: 0.83        // déficit ~17 %
        case .maintain: 1.0
        case .bulk: 1.12       // surplus ~12 %
        }
    }

    /// Protéines recommandées (g par kg de poids de corps)
    var proteinPerKg: Double {
        switch self {
        case .cut: 2.2         // préserve le muscle en déficit
        case .maintain: 1.6
        case .bulk: 1.8
        }
    }

    var blurb: String {
        switch self {
        case .cut: "Déficit d'environ 17 % pour perdre du gras en préservant le muscle."
        case .maintain: "L'équilibre : tu manges ce que tu dépenses."
        case .bulk: "Surplus d'environ 12 % pour construire du muscle."
        }
    }
}

// MARK: - Plan calculé

struct NutritionPlan {
    let bmr: Double            // métabolisme de base
    let tdee: Double           // dépense totale estimée
    let targetKcal: Double     // objectif du jour selon le régime
    let proteinG: Double
    let fatG: Double
    let carbsG: Double
}

// MARK: - Calculs (Mifflin-St Jeor + activité réellement mesurée par l'app)

enum NutritionPlanner {

    /// Moyenne d'activités par semaine sur les 4 dernières semaines (séances + courses)
    static func weeklyActivities(context: ModelContext) -> Double {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now) else { return 0 }
        let sessions = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= cutoff }))) ?? 0
        let runs = (try? context.fetchCount(FetchDescriptor<RunSession>(
            predicate: #Predicate { $0.date >= cutoff }))) ?? 0
        return Double(sessions + runs) / 4.0
    }

    static func plan(weightKg: Double, heightCm: Int, age: Int, sex: UserSex,
                     weeklyActivities: Double, goal: NutritionGoal) -> NutritionPlan {
        // Mifflin-St Jeor
        let sexOffset: Double = switch sex {
        case .male: 5
        case .female: -161
        case .unspecified: -78    // moyenne des deux
        }
        let bmr = 10 * weightKg + 6.25 * Double(heightCm) - 5 * Double(age) + sexOffset

        // Facteur d'activité calibré sur les activités réellement enregistrées :
        // 1.2 (sédentaire) + ~0.055 par activité hebdomadaire, plafonné à 1.75
        let factor = min(1.2 + 0.055 * weeklyActivities, 1.75)
        let tdee = bmr * factor

        // Jamais sous le métabolisme de base, même en sèche
        let target = max(tdee * goal.calorieFactor, bmr)

        let protein = goal.proteinPerKg * weightKg
        let fat = 1.0 * weightKg
        let carbs = max((target - protein * 4 - fat * 9) / 4, 0)

        return NutritionPlan(bmr: bmr, tdee: tdee, targetKcal: target,
                             proteinG: protein, fatG: fat, carbsG: carbs)
    }
}

extension NutritionPlanner {
    /// Publie l'objectif kcal dans l'App Group (lisible par le widget calories)
    /// et rafraîchit ses timelines. À appeler au lancement, au changement
    /// d'objectif/profil et à chaque modification du journal.
    @MainActor
    static func publishForWidget(context: ModelContext) {
        let d = UserDefaults.standard
        let weight = d.double(forKey: "profileWeightKg")
        let height = d.integer(forKey: "profileHeightCm")
        let age = d.integer(forKey: "profileAge")
        let sex = UserSex(rawValue: d.string(forKey: "profileSex") ?? "") ?? .unspecified
        let goal = NutritionGoal(rawValue: d.string(forKey: "nutritionGoal") ?? "") ?? .maintain
        let result = plan(weightKg: weight > 0 ? weight : 70,
                          heightCm: height > 0 ? height : 175,
                          age: age > 0 ? age : 25,
                          sex: sex,
                          weeklyActivities: weeklyActivities(context: context),
                          goal: goal)
        SharedStore.groupDefaults?.set(result.targetKcal, forKey: SharedStore.nutritionTargetKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "CalorieWidget")
    }
}

// MARK: - Calories brûlées (estimation MET)

enum CalorieEstimator {
    /// Musculation : MET ≈ 5.0 (effort modéré à soutenu avec repos)
    static func workoutKcal(durationSeconds: Int, weightKg: Double) -> Int {
        guard weightKg > 0, durationSeconds > 0 else { return 0 }
        return Int(5.0 * weightKg * Double(durationSeconds) / 3600)
    }

    /// Course : ≈ 1 kcal par kg et par km (bonne approximation indépendante de l'allure)
    static func runKcal(distanceKm: Double, weightKg: Double) -> Int {
        guard weightKg > 0, distanceKm > 0 else { return 0 }
        return Int(weightKg * distanceKm)
    }
}

// MARK: - Catalogue d'aliments (table CIQUAL 2020, ANSES, licence ouverte Etalab)

struct CiqualFood: Codable, Identifiable, Hashable {
    let n: String              // nom
    let g: Int                 // catégorie (FoodCategory)
    let k: Double              // kcal / 100 g
    let p: Double              // protéines g / 100 g
    let c: Double              // glucides g / 100 g
    let f: Double              // lipides g / 100 g

    var id: String { n }
    var name: String { n }
    var category: FoodCategory { FoodCategory(rawValue: g) ?? .misc }
}

// MARK: - Catégories d'aliments (groupes CIQUAL regroupés)

enum FoodCategory: Int, CaseIterable, Identifiable {
    case dishes = 0        // entrées et plats composés
    case fruitsVeg = 1     // fruits, légumes, légumineuses
    case cereals = 2       // produits céréaliers
    case meatFish = 3      // viandes, œufs, poissons
    case dairy = 4         // produits laitiers
    case drinks = 5        // boissons
    case sweets = 6        // produits sucrés + glaces
    case fats = 7          // matières grasses
    case misc = 8          // divers

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .dishes: "Plats"
        case .fruitsVeg: "Fruits & légumes"
        case .cereals: "Féculents"
        case .meatFish: "Viandes & poissons"
        case .dairy: "Laitages"
        case .drinks: "Boissons"
        case .sweets: "Sucré"
        case .fats: "Mat. grasses"
        case .misc: "Divers"
        }
    }

    var emoji: String {
        switch self {
        case .dishes: "🍲"
        case .fruitsVeg: "🥦"
        case .cereals: "🌾"
        case .meatFish: "🍗"
        case .dairy: "🧀"
        case .drinks: "🥤"
        case .sweets: "🍬"
        case .fats: "🧈"
        case .misc: "🧂"
        }
    }
}

enum FoodCatalog {
    static let all: [CiqualFood] = {
        func load(_ resource: String) -> [CiqualFood] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let items = try? JSONDecoder().decode([CiqualFood].self, from: data)
            else { return [] }
            return items
        }
        let ciqual = load("foods_ciqual")
        assert(!ciqual.isEmpty, "foods_ciqual.json introuvable dans le bundle")
        // foods_custom.json : compléments hors CIQUAL (whey, sodas de marque…),
        // valeurs issues des étiquettes produits
        return (ciqual + load("foods_custom"))
            .sorted { $0.n.localizedCaseInsensitiveCompare($1.n) == .orderedAscending }
    }()

    /// Recherche insensible à la casse et aux accents, filtrable par catégorie
    static func search(_ query: String, category: FoodCategory? = nil) -> [CiqualFood] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var results = all
        if let category {
            results = results.filter { $0.g == category.rawValue }
        }
        if !trimmed.isEmpty {
            results = results.filter { $0.n.localizedStandardContains(trimmed) }
        } else if category == nil {
            results = Array(results.prefix(80))
        }
        return results
    }
}

// MARK: - Repas

enum MealKind: String, CaseIterable, Identifiable {
    case breakfast = "Petit-déjeuner"
    case lunch = "Déjeuner"
    case dinner = "Dîner"
    case snack = "Collation"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .breakfast: "cup.and.saucer.fill"
        case .lunch: "fork.knife"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }
}
