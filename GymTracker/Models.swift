import Foundation
import SwiftData

// MARK: - Séance type (template)

@Model
final class WorkoutTemplate {
    var name: String
    var subtitle: String
    var icon: String
    var order: Int

    @Relationship(deleteRule: .cascade, inverse: \ExerciseTemplate.workout)
    var exercises: [ExerciseTemplate] = []

    init(name: String, subtitle: String = "", icon: String = "dumbbell.fill", order: Int = 0) {
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.order = order
    }

    var sortedExercises: [ExerciseTemplate] {
        exercises.sorted { $0.order < $1.order }
    }
}

// MARK: - Exercice d'une séance type

@Model
final class ExerciseTemplate {
    var name: String
    var targetSets: Int
    var repRange: String        // ex : "6-8"
    var restSeconds: Int
    var notes: String
    var order: Int
    /// ID de l'exercice dans le catalogue embarqué (GIF, instructions, muscles)
    var catalogID: String?
    var workout: WorkoutTemplate?

    init(name: String, targetSets: Int, repRange: String, restSeconds: Int, notes: String = "", order: Int = 0, catalogID: String? = nil) {
        self.name = name
        self.targetSets = targetSets
        self.repRange = repRange
        self.restSeconds = restSeconds
        self.notes = notes
        self.order = order
        self.catalogID = catalogID
    }
}

// MARK: - Séance réalisée (historique)

@Model
final class WorkoutSession {
    var date: Date
    var templateName: String
    var durationSeconds: Int

    @Relationship(deleteRule: .cascade, inverse: \SetRecord.session)
    var sets: [SetRecord] = []

    init(date: Date = .now, templateName: String, durationSeconds: Int = 0) {
        self.date = date
        self.templateName = templateName
        self.durationSeconds = durationSeconds
    }

    var totalVolume: Double {
        sets.reduce(0) { $0 + Double($1.reps) * $1.weight }
    }
}

// MARK: - Course enregistrée (mode running)

@Model
final class RunSession {
    var date: Date
    var distanceMeters: Double
    var durationSeconds: Int
    /// Tracé GPS encodé : suite de "lat,lon" séparés par ";"
    var routeEncoded: String

    init(date: Date = .now, distanceMeters: Double = 0, durationSeconds: Int = 0, routeEncoded: String = "") {
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.routeEncoded = routeEncoded
    }

    /// Allure moyenne en secondes par km
    var averagePaceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return Double(durationSeconds) / (distanceMeters / 1000)
    }

    var distanceKm: Double { distanceMeters / 1000 }

    /// Coordonnées décodées [(lat, lon)]
    var routePoints: [(lat: Double, lon: Double)] {
        routeEncoded.split(separator: ";").compactMap { pair in
            let c = pair.split(separator: ",")
            guard c.count == 2, let lat = Double(c[0]), let lon = Double(c[1]) else { return nil }
            return (lat, lon)
        }
    }
}

// MARK: - Entrée du journal alimentaire (Premium)

@Model
final class FoodEntry {
    var date: Date
    var name: String
    var grams: Double
    // Valeurs pour 100 g figées à la saisie (le catalogue peut évoluer)
    var kcalPer100: Double
    var proteinPer100: Double
    var carbsPer100: Double
    var fatPer100: Double
    var meal: String
    var category: Int = 8      // FoodCategory (défaut : divers, pour la migration)
    /// UUID des échantillons Apple Santé liés (séparés par des virgules),
    /// pour supprimer les données Santé avec l'entrée
    var healthIDs: String = ""

    init(date: Date = .now, name: String, grams: Double,
         kcalPer100: Double, proteinPer100: Double,
         carbsPer100: Double, fatPer100: Double, meal: String, category: Int = 8) {
        self.date = date
        self.name = name
        self.grams = grams
        self.kcalPer100 = kcalPer100
        self.proteinPer100 = proteinPer100
        self.carbsPer100 = carbsPer100
        self.fatPer100 = fatPer100
        self.meal = meal
        self.category = category
    }

    var kcal: Double { kcalPer100 * grams / 100 }
    var protein: Double { proteinPer100 * grams / 100 }
    var carbs: Double { carbsPer100 * grams / 100 }
    var fat: Double { fatPer100 * grams / 100 }
}

// MARK: - Compléments quotidiens (checklist)

@Model
final class Supplement {
    var name: String
    var emoji: String
    var dose: String          // libre : « 5 g », « 1 gélule », « 30 g »
    var order: Int
    var isActive: Bool

    init(name: String, emoji: String = "💊", dose: String = "", order: Int = 0, isActive: Bool = true) {
        self.name = name
        self.emoji = emoji
        self.dose = dose
        self.order = order
        self.isActive = isActive
    }
}

/// Une prise cochée, un jour donné (date ramenée au début de journée)
@Model
final class SupplementIntake {
    var date: Date
    var supplementName: String

    init(date: Date, supplementName: String) {
        self.date = Calendar.current.startOfDay(for: date)
        self.supplementName = supplementName
    }
}

// MARK: - Conteneur SwiftData partagé (App Group)
// Ce fichier appartient aux DEUX cibles : l'app et la widget extension lisent
// la même base via le conteneur du groupe `group.fr.devshield.gymtracker`.

enum SharedStore {
    static let appGroupID = "group.fr.devshield.gymtracker"

    /// Préférences partagées app ↔ widgets
    static var groupDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    /// Objectif kcal du jour, publié par l'app pour le widget calories
    static let nutritionTargetKey = "widget.nutritionTargetKcal"

    static var schema: Schema {
        Schema([WorkoutTemplate.self, ExerciseTemplate.self,
                WorkoutSession.self, SetRecord.self, RunSession.self,
                FoodEntry.self, Supplement.self, SupplementIntake.self])
    }

    static func makeContainer() throws -> ModelContainer {
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            // Entitlement App Group absent : repli sur la base locale historique
            return try ModelContainer(for: schema)
        }
        migrateLegacyStoreIfNeeded(to: groupURL)
        let config = ModelConfiguration(url: groupURL.appendingPathComponent("GymTracker.store"))
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Copie unique de l'ancienne base locale (avant App Group) vers le conteneur partagé,
    /// pour ne pas perdre les données déjà enregistrées sur l'appareil.
    private static func migrateLegacyStoreIfNeeded(to groupURL: URL) {
        let fm = FileManager.default
        let target = groupURL.appendingPathComponent("GymTracker.store")
        guard !fm.fileExists(atPath: target.path) else { return }
        let legacy = URL.applicationSupportDirectory.appending(path: "default.store")
        guard fm.fileExists(atPath: legacy.path) else { return }
        for suffix in ["", "-shm", "-wal"] {
            try? fm.copyItem(
                at: URL.applicationSupportDirectory.appending(path: "default.store" + suffix),
                to: groupURL.appendingPathComponent("GymTracker.store" + suffix)
            )
        }
    }
}

// MARK: - Formatage allure / durée

enum PaceFormatter {
    /// 372 s/km -> "6'12\"/km"
    static func string(secPerKm: Double) -> String {
        guard secPerKm > 0, secPerKm.isFinite else { return "-" }
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d'%02d\"/km", m, s)
    }

    /// 3725 s -> "1:02:05" ou "12:05"
    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Série enregistrée

@Model
final class SetRecord {
    var exerciseName: String
    var setIndex: Int
    var reps: Int
    var weight: Double          // kg — 0 pour le poids du corps
    var date: Date
    var session: WorkoutSession?

    init(exerciseName: String, setIndex: Int, reps: Int, weight: Double, date: Date = .now) {
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.reps = reps
        self.weight = weight
        self.date = date
    }
}
