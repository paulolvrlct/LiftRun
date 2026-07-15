import SwiftUI
import SwiftData

// MARK: - Liste des séances

struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]

    @ObservedObject private var premium = PremiumStore.shared
    @State private var activeTemplate: WorkoutTemplate?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(templates) { template in
                        TemplateCard(template: template) {
                            activeTemplate = template
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Séances")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Offre gratuite : 3 séances max, au-delà c'est Premium
                        guard templates.count < PremiumStore.FreeTier.maxTemplates || premium.isPremium else {
                            showPaywall = true
                            return
                        }
                        let t = WorkoutTemplate(name: "Nouvelle séance", order: templates.count)
                        context.insert(t)
                        try? context.save()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .fullScreenCover(item: $activeTemplate) { template in
                ActiveWorkoutView(template: template)
            }
        }
    }
}

// MARK: - Carte séance

private struct TemplateCard: View {
    @Bindable var template: WorkoutTemplate
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(colors: [.indigo, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).font(.headline)
                    Text(template.subtitle.isEmpty ? "\(template.exercises.count) exercices" : template.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    TemplateEditorView(template: template)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            }

            // Aperçu des exercices
            VStack(alignment: .leading, spacing: 4) {
                ForEach(template.sortedExercises.prefix(5)) { ex in
                    HStack {
                        Text(ex.name).font(.footnote)
                        Spacer()
                        Text("\(ex.targetSets) × \(ex.repRange)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, 4)

            Button(action: onStart) {
                Label("Démarrer", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

// MARK: - Éditeur de séance

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: WorkoutTemplate
    @State private var showLibraryPicker = false

    var body: some View {
        Form {
            Section("Séance") {
                TextField("Nom", text: $template.name)
                TextField("Sous-titre", text: $template.subtitle)
            }

            Section("Exercices") {
                ForEach(template.sortedExercises) { ex in
                    NavigationLink {
                        ExerciseEditorView(exercise: ex)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(ex.name)
                            Text("\(ex.targetSets) × \(ex.repRange) · repos \(ex.restSeconds) s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let sorted = template.sortedExercises
                    for i in offsets { context.delete(sorted[i]) }
                    try? context.save()
                }

                Button {
                    showLibraryPicker = true
                } label: {
                    Label("Ajouter depuis la bibliothèque", systemImage: "books.vertical.fill")
                }

                Button {
                    let ex = ExerciseTemplate(name: "Nouvel exercice", targetSets: 3,
                                              repRange: "8-12", restSeconds: 90,
                                              order: template.exercises.count)
                    ex.workout = template
                    context.insert(ex)
                    try? context.save()
                } label: {
                    Label("Ajouter un exercice vierge", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Button("Supprimer la séance", role: .destructive) {
                    context.delete(template)
                    try? context.save()
                    dismiss()
                }
            }
        }
        .navigationTitle("Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLibraryPicker) {
            ExerciseLibraryView { catalogEx in
                let ex = ExerciseTemplate(
                    name: catalogEx.name.capitalized,
                    targetSets: 3,
                    repRange: "8-12",
                    restSeconds: 90,
                    notes: catalogEx.steps.joined(separator: " "),
                    order: template.exercises.count,
                    catalogID: catalogEx.id
                )
                ex.workout = template
                context.insert(ex)
                try? context.save()
            }
        }
    }
}

// MARK: - Éditeur d'exercice

struct ExerciseEditorView: View {
    @Bindable var exercise: ExerciseTemplate

    var body: some View {
        Form {
            if let catalogEx = ExerciseCatalog.find(id: exercise.catalogID) {
                Section {
                    ExercisePhotoBanner(exercise: catalogEx)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Exercice") {
                TextField("Nom", text: $exercise.name)
            }
            Section("Objectifs") {
                Stepper("Séries : \(exercise.targetSets)", value: $exercise.targetSets, in: 1...10)
                TextField("Fourchette de reps (ex : 8-12)", text: $exercise.repRange)
                Stepper("Repos : \(exercise.restSeconds) s", value: $exercise.restSeconds, in: 15...300, step: 15)
            }
            Section("Consignes techniques") {
                TextField("Notes", text: $exercise.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
