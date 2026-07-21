import SwiftUI
import SwiftData
import Charts

struct ProgressChartsView: View {
    @Query(sort: \SetRecord.date) private var allSets: [SetRecord]
    @State private var selectedExercise: String = ""
    @State private var scope: Scope = .strength

    enum Scope: String, CaseIterable {
        case strength = "Musculation"
        case running = "Course"
    }

    /// Noms d'exercices distincts présents dans l'historique
    private var exerciseNames: [String] {
        Array(Set(allSets.map(\.exerciseName))).sorted()
    }

    /// Charge max par jour pour l'exercice sélectionné
    private var dataPoints: [(date: Date, maxWeight: Double)] {
        let calendar = Calendar.current
        let filtered = allSets.filter { $0.exerciseName == selectedExercise && $0.weight > 0 }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (date: $0.key, maxWeight: $0.value.map(\.weight).max() ?? 0) }
            .sorted { $0.date < $1.date }
    }

    private var progression: Double? {
        guard let first = dataPoints.first?.maxWeight,
              let last = dataPoints.last?.maxWeight,
              dataPoints.count > 1, first > 0 else { return nil }
        return (last - first) / first * 100
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Activité", selection: $scope) {
                        ForEach(Scope.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    switch scope {
                    case .strength: strengthSection
                    case .running: RunProgressSection()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progression")
            .onAppear {
                if selectedExercise.isEmpty { selectedExercise = exerciseNames.first ?? "" }
            }
        }
    }

    // MARK: Musculation

    @ViewBuilder
    private var strengthSection: some View {
        if exerciseNames.isEmpty {
            ContentUnavailableView(
                "Pas encore de données",
                systemImage: "chart.xyaxis.line",
                description: Text("Termine ta première séance pour voir tes courbes de progression.")
            )
            .padding(.top, 80)
        } else {
            exercisePicker
            chartCard
            statsCard
            oneRepMaxCard
        }
    }

    // MARK: 1RM estimé (max théorique)

    @ViewBuilder
    private var oneRepMaxCard: some View {
        let e1rm = StrengthMath.best1RM(exerciseName: selectedExercise, in: allSets)
        if e1rm > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label("Max théorique (1RM estimé)", systemImage: "bolt.heart.fill")
                    .font(.headline)
                Text("\(e1rm.clean) kg")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.indigo)
                Text("Estimé par la formule d'Epley à partir de ta meilleure série. Indicatif : ne tente pas un 1RM réel sans échauffement ni pareur.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
    }

    // MARK: Sélecteur d'exercice

    private var exercisePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(exerciseNames, id: \.self) { name in
                    Button {
                        selectedExercise = name
                    } label: {
                        Text(name)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedExercise == name ? Color.indigo : Color(.tertiarySystemFill),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedExercise == name ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Graphique

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Charge max · \(selectedExercise)")
                .font(.headline)

            if dataPoints.isEmpty {
                Text("Exercice au poids du corps ou aucune charge enregistrée.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(dataPoints, id: \.date) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Charge", point.maxWeight)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.indigo.opacity(0.3), .indigo.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Charge", point.maxWeight)
                    )
                    .foregroundStyle(.indigo)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Charge", point.maxWeight)
                    )
                    .foregroundStyle(.indigo)
                    .symbolSize(40)
                }
                .chartYAxisLabel("kg")
                .frame(height: 230)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    // MARK: Stats rapides

    private var statsCard: some View {
        HStack(spacing: 12) {
            statTile(title: "Record",
                     value: dataPoints.map(\.maxWeight).max().map { "\($0.clean) kg" } ?? "-",
                     icon: "trophy.fill", color: .orange)
            statTile(title: "Dernière",
                     value: dataPoints.last.map { "\($0.maxWeight.clean) kg" } ?? "-",
                     icon: "clock.fill", color: .indigo)
            statTile(title: "Évolution",
                     value: progression.map { String(format: "%+.0f %%", $0) } ?? "-",
                     icon: "arrow.up.right", color: .green)
        }
    }

    private func statTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}
