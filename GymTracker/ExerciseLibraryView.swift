import SwiftUI

// MARK: - Bibliothèque d'exercices (1 324 exos)

struct ExerciseLibraryView: View {
    /// En mode picker (depuis l'éditeur de séance), renvoie l'exercice choisi
    var onSelect: ((CatalogExercise) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedEquipment: String? = nil

    private var filtered: [CatalogExercise] {
        ExerciseCatalog.all.filter { ex in
            (selectedCategory == nil || ex.category == selectedCategory)
            && (selectedEquipment == nil || ex.equipment == selectedEquipment)
            && (searchText.isEmpty
                || ex.name.localizedCaseInsensitiveContains(searchText)
                || ex.target.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterBar
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("\(filtered.count) exercices") {
                    ForEach(filtered.prefix(200)) { ex in
                        NavigationLink {
                            ExerciseDetailView(exercise: ex, onSelect: onSelect.map { select in
                                { select(ex); dismiss() }
                            })
                        } label: {
                            LibraryRow(exercise: ex)
                        }
                    }
                    if filtered.count > 200 {
                        Text("Affine ta recherche pour voir plus de résultats…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Nom ou muscle ciblé (EN)")
            .navigationTitle(onSelect == nil ? "Bibliothèque" : "Choisir un exercice")
            .toolbar {
                if onSelect != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fermer") { dismiss() }
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("Toutes zones", isOn: selectedCategory == nil) { selectedCategory = nil }
                    ForEach(ExerciseCatalog.categories, id: \.self) { cat in
                        filterChip(CatalogExercise.categoryFR[cat] ?? cat,
                                   isOn: selectedCategory == cat) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("Tout matériel", isOn: selectedEquipment == nil) { selectedEquipment = nil }
                    ForEach(ExerciseCatalog.equipments, id: \.self) { eq in
                        filterChip(CatalogExercise.equipmentFR[eq] ?? eq,
                                   isOn: selectedEquipment == eq) {
                            selectedEquipment = selectedEquipment == eq ? nil : eq
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    private func filterChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.indigo : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ligne de liste

private struct LibraryRow: View {
    let exercise: CatalogExercise

    var body: some View {
        HStack(spacing: 12) {
            if let photo = exercise.photoURLs.first {
                AsyncImage(url: photo) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ExerciseIllustration(exercise: exercise, size: 52)
                    }
                }
                .frame(width: 52, height: 52)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ExerciseIllustration(exercise: exercise, size: 52)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name.capitalized)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(exercise.categoryFR)
                    Text("·")
                    Text(exercise.equipmentFR)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Fiche exercice

struct ExerciseDetailView: View {
    let exercise: CatalogExercise
    var onSelect: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Photos Free Exercise DB (domaine public), sinon illustration vectorielle
                ExercisePhotoBanner(exercise: exercise)

                // Badges
                HStack(spacing: 8) {
                    badge(exercise.categoryFR, icon: "figure.arms.open", color: .indigo)
                    badge(exercise.equipmentFR, icon: "dumbbell.fill", color: .purple)
                }

                // Muscles
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Muscle ciblé : ").foregroundStyle(.secondary)
                        + Text(exercise.target.capitalized).fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "target").foregroundStyle(.red)
                    }
                    .font(.subheadline)

                    if !exercise.secondary.isEmpty {
                        Label {
                            Text("Secondaires : ").foregroundStyle(.secondary)
                            + Text(exercise.secondary.map(\.capitalized).joined(separator: ", "))
                        } icon: {
                            Image(systemName: "circle.dashed").foregroundStyle(.orange)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Instructions — français si dispo, sinon anglais (dataset source)
                let frSteps = ExerciseTranslationsFR.steps(for: exercise.id)
                let displaySteps = frSteps ?? exercise.steps
                if !displaySteps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Exécution")
                                .font(.headline)
                            Spacer()
                            if frSteps == nil {
                                Text("EN")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(Array(displaySteps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.bold))
                                    .frame(width: 22, height: 22)
                                    .background(Color.indigo.opacity(0.15), in: Circle())
                                    .foregroundStyle(.indigo)
                                Text(step)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exercise.name.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let onSelect {
                Button {
                    onSelect()
                } label: {
                    Label("Ajouter à la séance", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .padding()
                .background(.regularMaterial)
            }
        }
    }

    private func badge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
