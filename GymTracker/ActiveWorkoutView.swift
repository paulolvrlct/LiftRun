import SwiftUI
import SwiftData
import AudioToolbox

// MARK: - Série en cours de saisie (draft, non persisté avant la fin)

struct DraftSet: Identifiable {
    let id = UUID()
    let exerciseName: String
    let setIndex: Int
    let reps: Int
    let weight: Double
}

// MARK: - Séance active

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate

    @Query(sort: \SetRecord.date, order: .reverse) private var history: [SetRecord]

    @State private var loggedSets: [DraftSet] = []
    @State private var startDate = Date.now
    @State private var showCancelAlert = false
    @State private var showCelebration = false
    @StateObject private var restTimer = RestTimerModel()

    /// Dernière série enregistrée pour cet exercice (dernière séance, dernière
    /// série de cette séance), pour pré-régler reps et poids.
    private func lastValues(for exercise: ExerciseTemplate) -> (reps: Int, weight: Double)? {
        history
            .filter { $0.exerciseName == exercise.name }
            .max { ($0.date, $0.setIndex) < ($1.date, $1.setIndex) }
            .map { ($0.reps, $0.weight) }
    }

    /// Nombre total de séries visées sur la séance
    private var targetSetCount: Int {
        template.sortedExercises.reduce(0) { $0 + $1.targetSets }
    }

    // Barre de progression de la séance
    private var sessionProgress: some View {
        let total = max(targetSetCount, 1)
        let done = min(loggedSets.count, total)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progression").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(done) / \(total) séries")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(total))
                .tint(.indigo)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    sessionProgress
                    ForEach(template.sortedExercises) { exercise in
                        ExerciseLogCard(
                            exercise: exercise,
                            sets: loggedSets.filter { $0.exerciseName == exercise.name },
                            last: lastValues(for: exercise),
                            onLog: { reps, weight in
                                logSet(exercise: exercise, reps: reps, weight: weight)
                            }
                        )
                    }
                }
                .padding()
                .padding(.bottom, restTimer.isRunning ? 120 : 20)
                // Rebond des pastilles de séries et des coches à chaque validation
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: loggedSets.count)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .destructive) { showCancelAlert = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminer") { finishWorkout() }
                        .fontWeight(.semibold)
                        .disabled(loggedSets.isEmpty)
                }
            }
            .overlay(alignment: .bottom) {
                if restTimer.isRunning {
                    RestTimerBar(timer: restTimer)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: restTimer.isRunning)
            // Célébration de fin de séance (confettis + stats)
            .overlay {
                if showCelebration {
                    WorkoutCelebrationView(
                        setCount: loggedSets.count,
                        volume: loggedSets.reduce(0) { $0 + Double($1.reps) * $1.weight },
                        durationSeconds: Int(Date.now.timeIntervalSince(startDate))
                    ) {
                        dismiss()
                    }
                    .transition(.opacity)
                }
            }
            .alert("Abandonner la séance ?", isPresented: $showCancelAlert) {
                Button("Continuer la séance", role: .cancel) {}
                Button("Abandonner", role: .destructive) {
                    restTimer.stop()   // coupe chrono, Live Activity et notification
                    dismiss()
                }
            } message: {
                Text("Les séries saisies ne seront pas enregistrées.")
            }
        }
    }

    private func logSet(exercise: ExerciseTemplate, reps: Int, weight: Double) {
        let index = loggedSets.filter { $0.exerciseName == exercise.name }.count + 1
        loggedSets.append(DraftSet(exerciseName: exercise.name, setIndex: index, reps: reps, weight: weight))
        restTimer.start(seconds: exercise.restSeconds, exerciseName: exercise.name, workoutName: template.name)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func finishWorkout() {
        let session = WorkoutSession(
            date: startDate,
            templateName: template.name,
            durationSeconds: Int(Date.now.timeIntervalSince(startDate))
        )
        context.insert(session)
        for draft in loggedSets {
            let record = SetRecord(exerciseName: draft.exerciseName, setIndex: draft.setIndex,
                                   reps: draft.reps, weight: draft.weight, date: startDate)
            record.session = session
            context.insert(record)
        }
        try? context.save()
        restTimer.stop()   // coupe chrono de repos, Live Activity et notification

        // Enregistre l'entraînement dans Apple Santé
        let duration = session.durationSeconds
        let weight = UserDefaults.standard.double(forKey: "profileWeightKg")
        let kcal = CalorieEstimator.workoutKcal(durationSeconds: duration,
                                                weightKg: weight > 0 ? weight : 70)
        Task {
            await HealthKitManager.shared.saveStrengthWorkout(
                start: startDate, durationSeconds: duration, kcal: kcal)
        }

        withAnimation(.easeOut(duration: 0.3)) { showCelebration = true }
    }
}

// MARK: - Carte exercice avec saisie

private struct ExerciseLogCard: View {
    let exercise: ExerciseTemplate
    let sets: [DraftSet]
    let last: (reps: Int, weight: Double)?
    var onLog: (Int, Double) -> Void

    @State private var reps: Int
    @State private var weight: Double
    @State private var showNotes = false
    @State private var showAnimation = false

    init(exercise: ExerciseTemplate, sets: [DraftSet],
         last: (reps: Int, weight: Double)?, onLog: @escaping (Int, Double) -> Void) {
        self.exercise = exercise
        self.sets = sets
        self.last = last
        self.onLog = onLog
        // pré-remplit avec la dernière performance, sinon des valeurs par défaut
        _reps = State(initialValue: last?.reps ?? 8)
        _weight = State(initialValue: last?.weight ?? 20)
    }

    private var catalogEx: CatalogExercise? { ExerciseCatalog.find(id: exercise.catalogID) }
    private var isDone: Bool { sets.count >= exercise.targetSets }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // En-tête
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.headline)
                    Text("Objectif : \(exercise.targetSets) × \(exercise.repRange) · repos \(exercise.restSeconds) s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let last {
                        Label(last.weight > 0
                              ? "Dernière : \(last.reps) × \(last.weight.clean) kg"
                              : "Dernière : \(last.reps) reps",
                              systemImage: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                    }
                }
                Spacer()
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
                if catalogEx != nil {
                    Button {
                        showAnimation = true
                    } label: {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.indigo)
                    }
                }
                if !exercise.notes.isEmpty {
                    Button {
                        showNotes.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if showNotes {
                Text(exercise.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }

            // Séries validées
            if !sets.isEmpty {
                HStack(spacing: 8) {
                    ForEach(sets) { s in
                        Text(s.weight > 0 ? "\(s.reps) × \(s.weight.clean) kg" : "\(s.reps) reps")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.indigo.opacity(0.12), in: Capsule())
                            .foregroundStyle(.indigo)
                    }
                }
            }

            // Saisie
            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text("REPS").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        stepButton("minus") { if reps > 1 { reps -= 1 } }
                        Text("\(reps)")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .frame(minWidth: 40)
                        stepButton("plus") { reps += 1 }
                    }
                }

                VStack(spacing: 2) {
                    Text("POIDS (KG)").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        stepButton("minus") { if weight >= 1.25 { weight -= 1.25 } }
                        Text(weight.clean)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .frame(minWidth: 52)
                        stepButton("plus") { weight += 1.25 }
                    }
                }

                Spacer()

                Button {
                    onLog(reps, weight)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(isDone ? .green : .indigo)
                .clipShape(Circle())
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .sheet(isPresented: $showAnimation) {
            if let catalogEx {
                NavigationStack {
                    ExerciseDetailView(exercise: catalogEx)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Fermer") { showAnimation = false }
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timer de repos

@MainActor
final class RestTimerModel: ObservableObject {
    @Published var remaining: Int = 0
    @Published var total: Int = 1
    @Published var isRunning = false

    private var timer: Timer?
    private var endDate = Date.now
    private var exerciseName = ""
    private var workoutName = ""

    func start(seconds: Int, exerciseName: String, workoutName: String) {
        stop()
        self.exerciseName = exerciseName
        self.workoutName = workoutName
        total = max(seconds, 1)
        remaining = seconds
        // le décompte s'appuie sur une date de fin : même référence que la
        // Dynamic Island, et toujours juste après un passage en arrière-plan
        endDate = Date.now.addingTimeInterval(TimeInterval(seconds))
        isRunning = true

        // Dynamic Island + écran verrouillé + notification de fin
        LiveActivityManager.shared.startRest(exerciseName: exerciseName, workoutName: workoutName, seconds: seconds)
        NotificationManager.shared.scheduleRestEnd(after: seconds, exerciseName: exerciseName)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let left = Int(ceil(endDate.timeIntervalSinceNow))
        if left > 0 {
            remaining = left
        } else {
            remaining = 0
            // son + haptique seulement si la fin vient d'arriver
            // (pas de fanfare tardive au retour dans l'app)
            if endDate.timeIntervalSinceNow > -3 {
                AudioServicesPlaySystemSound(1007)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            stop()
        }
    }

    func add(_ seconds: Int) {
        endDate = endDate.addingTimeInterval(TimeInterval(seconds))
        remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        total += seconds
        LiveActivityManager.shared.updateRest(exerciseName: exerciseName, endDate: endDate, totalSeconds: total)
        NotificationManager.shared.scheduleRestEnd(after: remaining, exerciseName: exerciseName)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        LiveActivityManager.shared.endRest()
        NotificationManager.shared.cancelRestEnd()
    }
}

private struct RestTimerBar: View {
    @ObservedObject var timer: RestTimerModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(timer.remaining) / CGFloat(timer.total))
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.remaining)
                Text("\(timer.remaining)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 1) {
                Text("Repos").font(.headline)
                Text("Prochaine série dans \(timer.remaining) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("−15 s") { timer.add(-15) }
                .buttonStyle(.bordered)
                .font(.footnote.weight(.semibold))
                .disabled(timer.remaining <= 15)

            Button("+15 s") { timer.add(15) }
                .buttonStyle(.bordered)
                .font(.footnote.weight(.semibold))

            Button {
                timer.stop()
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

// MARK: - Helpers

extension Double {
    /// "20" au lieu de "20.0", "22.5" conservé
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", self)
            : String(format: "%.2f", self).replacingOccurrences(of: ".00", with: "")
    }
}
