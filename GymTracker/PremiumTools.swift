import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 1RM (max théorique) et records personnels

enum StrengthMath {
    /// Estimation du 1RM par la formule d'Epley (reps > 0)
    static func epley1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Meilleur 1RM estimé de l'historique pour un exercice
    static func best1RM(exerciseName: String, in records: [SetRecord]) -> Double {
        records
            .filter { $0.exerciseName == exerciseName && $0.weight > 0 }
            .map { epley1RM(weight: $0.weight, reps: $0.reps) }
            .max() ?? 0
    }

    /// Charge maximale jamais soulevée pour un exercice
    static func maxWeight(exerciseName: String, in records: [SetRecord]) -> Double {
        records.filter { $0.exerciseName == exerciseName }.map(\.weight).max() ?? 0
    }
}

// MARK: - Calculateur de disques (Premium)

struct PlateCalculatorView: View {
    @AppStorage("plateBarWeight") private var barWeight = 20.0
    @State private var target = 60.0

    /// Disques disponibles par côté (kg), du plus lourd au plus léger
    private let plates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    private var perSide: [Double] {
        var remaining = (target - barWeight) / 2
        guard remaining > 0 else { return [] }
        var result: [Double] = []
        for plate in plates {
            while remaining >= plate - 0.001 {
                result.append(plate)
                remaining -= plate
            }
        }
        return result
    }

    private var achievable: Double {
        barWeight + perSide.reduce(0, +) * 2
    }

    var body: some View {
        Form {
            Section("Objectif") {
                Stepper(String(format: "Poids visé : %.1f kg", target),
                        value: $target, in: barWeight...400, step: 2.5)
                Picker("Barre", selection: $barWeight) {
                    Text("Olympique · 20 kg").tag(20.0)
                    Text("Femme · 15 kg").tag(15.0)
                    Text("Courte · 10 kg").tag(10.0)
                    Text("EZ · 7 kg").tag(7.0)
                }
            }

            Section("Disques par côté") {
                if perSide.isEmpty {
                    Text("La barre seule suffit (ou objectif trop léger).")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ForEach(Array(perSide.enumerated()), id: \.offset) { _, plate in
                            Text(plate.clean)
                                .font(.headline.monospacedDigit())
                                .frame(width: 52, height: 52)
                                .background(Color.indigo.opacity(0.15), in: Circle())
                                .foregroundStyle(.indigo)
                        }
                    }
                    LabeledContent("Chargé de chaque côté",
                                   value: "\(perSide.count) disque\(perSide.count > 1 ? "s" : "")")
                }
                if abs(achievable - target) > 0.01 {
                    Label(String(format: "Atteignable : %.1f kg (disques limités)", achievable),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Calcul des disques")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Export CSV (Premium)

enum CSVExporter {
    private static func escape(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n")
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }

    /// Historique des séries (musculation) en CSV
    static func workoutsCSV(context: ModelContext) -> URL? {
        let sets = (try? context.fetch(FetchDescriptor<SetRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var lines = ["date,exercice,serie,reps,poids_kg"]
        let df = ISO8601DateFormatter()
        for s in sets {
            lines.append([df.string(from: s.date), escape(s.exerciseName),
                          "\(s.setIndex)", "\(s.reps)", s.weight.clean].joined(separator: ","))
        }
        return write(lines.joined(separator: "\n"), name: "LiftRun-seances.csv")
    }

    /// Journal alimentaire en CSV
    static func nutritionCSV(context: ModelContext) -> URL? {
        let entries = (try? context.fetch(FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var lines = ["date,repas,aliment,grammes,kcal,proteines_g,glucides_g,lipides_g"]
        let df = ISO8601DateFormatter()
        for e in entries {
            lines.append([df.string(from: e.date), escape(e.meal), escape(e.name),
                          e.grams.clean, "\(Int(e.kcal))", e.protein.clean,
                          e.carbs.clean, e.fat.clean].joined(separator: ","))
        }
        return write(lines.joined(separator: "\n"), name: "LiftRun-nutrition.csv")
    }

    private static func write(_ content: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try content.write(to: url, atomically: true, encoding: .utf8); return url }
        catch { return nil }
    }
}

// MARK: - Boîte à outils (Premium)

struct WorkoutToolsView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var premium = PremiumStore.shared
    @State private var showPaywall = false
    @State private var workoutCSV: URL?
    @State private var nutritionCSV: URL?

    var body: some View {
        List {
            if premium.isPremium {
                Section("Outils") {
                    NavigationLink {
                        PlateCalculatorView()
                    } label: {
                        Label("Calcul des disques", systemImage: "circle.hexagongrid.fill")
                    }
                }
                Section {
                    Button {
                        workoutCSV = CSVExporter.workoutsCSV(context: context)
                    } label: {
                        Label("Historique des séances (CSV)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        nutritionCSV = CSVExporter.nutritionCSV(context: context)
                    } label: {
                        Label("Journal alimentaire (CSV)", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Exporter mes données")
                } footer: {
                    Text("Un fichier CSV ouvrable dans Numbers ou Excel, à partager avec ton coach.")
                }
            } else {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 40)).foregroundStyle(.indigo)
                        Text("Outils Premium")
                            .font(.title3.weight(.semibold))
                        Text("Calcul des disques et export CSV de tes données.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Débloquer avec Premium", systemImage: "crown.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Outils")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $workoutCSV) { url in ShareSheet(url: url) }
        .sheet(item: $nutritionCSV) { url in ShareSheet(url: url) }
    }
}

// Petit wrapper pour partager un fichier
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Couleur d'accent (Premium, thème)

enum AccentTheme: String, CaseIterable, Identifiable {
    case indigo, purple, blue, teal, green, orange, pink, red
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .purple: .purple
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .red: .red
        }
    }

    var label: String {
        switch self {
        case .indigo: "Indigo"
        case .purple: "Violet"
        case .blue: "Bleu"
        case .teal: "Turquoise"
        case .green: "Vert"
        case .orange: "Orange"
        case .pink: "Rose"
        case .red: "Rouge"
        }
    }
}
