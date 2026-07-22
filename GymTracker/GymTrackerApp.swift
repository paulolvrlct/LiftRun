//   ____                ____   _      _        _      _
//  |  _ \   ___ __   __/ ___| | |__  (_)  ___ | |  __| |
//  | | | | / _ \\ \ / /\___ \ | '_ \ | | / _ \| | / _` |
//  | |_| ||  __/ \ V /  ___) || | | || ||  __/| || (_| |
//  |____/  \___|  \_/  |____/ |_| |_||_| \___||_| \__,_|
//
//  LiftRun · une app DevShield

import SwiftUI
import SwiftData

@main
struct GymTrackerApp: App {
    let container: ModelContainer

    init() {
        do {
            // Base dans l'App Group : partagée avec la widget extension
            container = try SharedStore.makeContainer()
            SeedData.seedIfNeeded(context: container.mainContext)
        } catch {
            fatalError("Impossible d'initialiser SwiftData : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

// MARK: - Programme pré-chargé (Pecs · Bras · Abdos)

enum SeedData {
    static func seedIfNeeded(context: ModelContext) {
        fixLegacyIcons(context: context)
        let descriptor = FetchDescriptor<WorkoutTemplate>()
        guard (try? context.fetchCount(descriptor)) == 0 else { return }

        // Séance A — Pectoraux
        let a = WorkoutTemplate(name: "Séance A", subtitle: "Pectoraux · 45-55 min", icon: "figure.strengthtraining.traditional", order: 0)
        a.exercises = [
            ExerciseTemplate(name: "Développé incliné barre", targetSets: 4, repRange: "6-8", restSeconds: 150,
                             notes: "Banc à 30°, omoplates serrées, barre au niveau du haut des pecs. Charge lourde, exécution stricte.", order: 0, catalogID: "0047"),
            ExerciseTemplate(name: "Développé incliné haltères", targetSets: 3, repRange: "8-12", restSeconds: 90,
                             notes: "Descente profonde pour l'étirement, coudes à ~45° du buste.", order: 1, catalogID: "0314"),
            ExerciseTemplate(name: "Chest press", targetSets: 3, repRange: "10-12", restSeconds: 90,
                             notes: "Tempo contrôlé (2 s descente), chercher la congestion.", order: 2, catalogID: "0577"),
            ExerciseTemplate(name: "Papillon (pec deck)", targetSets: 3, repRange: "12-15", restSeconds: 75,
                             notes: "Contraction tenue 1 s bras rapprochés, retour lent.", order: 3, catalogID: "0596"),
        ]

        // Séance B — Bras + Dos
        let b = WorkoutTemplate(name: "Séance B", subtitle: "Bras + Dos · 50-60 min", icon: "figure.strengthtraining.functional", order: 1)
        b.exercises = [
            ExerciseTemplate(name: "Tractions supination", targetSets: 4, repRange: "6-10", restSeconds: 120,
                             notes: "Prise largeur épaules, paumes vers soi. Descente contrôlée 2-3 s. Trop facile → lesté.", order: 0, catalogID: "1326"),
            ExerciseTemplate(name: "Curl barre EZ", targetSets: 3, repRange: "8-12", restSeconds: 90,
                             notes: "Coudes fixés le long du corps, pas d'élan du buste.", order: 1, catalogID: "0447"),
            ExerciseTemplate(name: "Curl marteau haltères", targetSets: 3, repRange: "10-12", restSeconds: 75,
                             notes: "Prise neutre : cible le brachial, épaissit le bras.", order: 2, catalogID: "1648"),
            ExerciseTemplate(name: "Dips prise serrée", targetSets: 3, repRange: "8-12", restSeconds: 90,
                             notes: "Buste vertical pour cibler les triceps. Coudes à 90°. Trop facile → lesté.", order: 3, catalogID: "0814"),
            ExerciseTemplate(name: "Extensions triceps poulie", targetSets: 3, repRange: "12-15", restSeconds: 60,
                             notes: "Coudes collés au corps, écarter la corde en bas, extension complète.", order: 4, catalogID: "0241"),
        ]

        // Séance C — Abdos
        let c = WorkoutTemplate(name: "Séance C", subtitle: "Abdos · 15-20 min", icon: "figure.core.training", order: 2)
        c.exercises = [
            ExerciseTemplate(name: "Crunch poulie haute", targetSets: 3, repRange: "10-15", restSeconds: 90,
                             notes: "Corde derrière la tête, enrouler le buste en soufflant. À charger progressivement.", order: 0, catalogID: "0175"),
            ExerciseTemplate(name: "Relevés de jambes suspendu", targetSets: 3, repRange: "8-15", restSeconds: 90,
                             notes: "Genoux (débutant) ou jambes tendues (avancé), sans balancier.", order: 1, catalogID: "0472"),
            ExerciseTemplate(name: "Gainage planche", targetSets: 3, repRange: "45-60 s", restSeconds: 60,
                             notes: "Bassin rétroversé, corps aligné. Noter les secondes dans « reps ».", order: 2, catalogID: "2135"),
            ExerciseTemplate(name: "Rotations russes", targetSets: 3, repRange: "12-20", restSeconds: 60,
                             notes: "Buste incliné, pieds décollés, rotation contrôlée avec disque léger.", order: 3, catalogID: "0687"),
        ]

        [a, b, c].forEach { context.insert($0) }
        context.saveLogging()
    }

    /// "figure.pullup" n'existe pas dans SF Symbols : les séances déjà créées
    /// avec cette icône s'affichaient sans logo.
    private static func fixLegacyIcons(context: ModelContext) {
        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        var changed = false
        for template in templates where template.icon == "figure.pullup" {
            template.icon = "figure.strengthtraining.functional"
            changed = true
        }
        if changed { context.saveLogging() }
    }
}
