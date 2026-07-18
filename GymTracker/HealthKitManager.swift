import Foundation
import HealthKit

// MARK: - Intégration Apple Santé (écriture uniquement)
// Séances et courses enregistrées comme entraînements, journal alimentaire
// vers les données nutrition. La lecture (ex. courses faites à la montre)
// viendra avec l'app watchOS.

@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()
    private init() {}

    private var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var writeTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(),
         HKQuantityType(.activeEnergyBurned),
         HKQuantityType(.distanceWalkingRunning),
         HKQuantityType(.dietaryEnergyConsumed),
         HKQuantityType(.dietaryProtein),
         HKQuantityType(.dietaryCarbohydrates),
         HKQuantityType(.dietaryFatTotal)]
    }

    /// Ne présente la demande qu'au premier appel ; no-op ensuite.
    private func ensureAuthorization() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: writeTypes, read: [])
    }

    // MARK: Entraînements

    /// Séance de musculation terminée
    func saveStrengthWorkout(start: Date, durationSeconds: Int, kcal: Int) async {
        await saveWorkout(activity: .traditionalStrengthTraining,
                          start: start, durationSeconds: durationSeconds,
                          kcal: kcal, distanceMeters: nil)
    }

    /// Course terminée
    func saveRun(start: Date, durationSeconds: Int, kcal: Int, distanceMeters: Double) async {
        await saveWorkout(activity: .running,
                          start: start, durationSeconds: durationSeconds,
                          kcal: kcal, distanceMeters: distanceMeters)
    }

    private func saveWorkout(activity: HKWorkoutActivityType, start: Date,
                             durationSeconds: Int, kcal: Int, distanceMeters: Double?) async {
        guard isAvailable, durationSeconds > 0 else { return }
        await ensureAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let end = start.addingTimeInterval(TimeInterval(durationSeconds))

        do {
            try await builder.beginCollection(at: start)
            var samples: [HKSample] = []
            if kcal > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(kcal)),
                    start: start, end: end))
            }
            if let distanceMeters, distanceMeters > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.distanceWalkingRunning),
                    quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
                    start: start, end: end))
            }
            if !samples.isEmpty {
                try await builder.addSamples(samples)
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Santé indisponible ou refusée : l'app reste pleinement fonctionnelle
        }
    }

    // MARK: Nutrition

    private var dietaryTypes: [(HKQuantityType, HKUnit)] {
        [(HKQuantityType(.dietaryEnergyConsumed), .kilocalorie()),
         (HKQuantityType(.dietaryProtein), .gram()),
         (HKQuantityType(.dietaryCarbohydrates), .gram()),
         (HKQuantityType(.dietaryFatTotal), .gram())]
    }

    /// Écrit un aliment consommé ; renvoie les UUID des échantillons créés
    /// (à conserver pour pouvoir les supprimer avec l'entrée du journal).
    func saveFood(kcal: Double, protein: Double, carbs: Double, fat: Double,
                  date: Date, name: String) async -> [String] {
        guard isAvailable else { return [] }
        await ensureAuthorization()

        let metadata = [HKMetadataKeyFoodType: name]
        let values = [kcal, protein, carbs, fat]
        var samples: [HKQuantitySample] = []
        for (index, (type, unit)) in dietaryTypes.enumerated() where values[index] > 0 {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: values[index]),
                start: date, end: date, metadata: metadata))
        }
        guard !samples.isEmpty else { return [] }
        do {
            try await store.save(samples)
            return samples.map { $0.uuid.uuidString }
        } catch {
            return []
        }
    }

    /// Supprime les échantillons Santé liés à une entrée du journal
    func deleteFoodSamples(ids: [String]) async {
        guard isAvailable else { return }
        let uuids = Set(ids.compactMap(UUID.init))
        guard !uuids.isEmpty else { return }

        for (type, _) in dietaryTypes {
            let predicate = HKQuery.predicateForObjects(with: uuids)
            let samples: [HKSample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                          limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                    continuation.resume(returning: results ?? [])
                }
                store.execute(query)
            }
            if !samples.isEmpty {
                try? await store.delete(samples)
            }
        }
    }
}
