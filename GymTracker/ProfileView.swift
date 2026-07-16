import SwiftUI

// MARK: - Profil utilisateur (UserDefaults via @AppStorage)

enum UserSex: String, CaseIterable, Identifiable {
    case male = "Homme"
    case female = "Femme"
    case unspecified = "Non précisé"
    var id: String { rawValue }
}

// MARK: - Licences et crédits (attributions requises)

struct CreditsView: View {
    var body: some View {
        List {
            Section("Catalogue d'exercices") {
                Text("Structure et instructions issues du dataset « exercises-dataset » © 2026 Hasan Emir Yıldırım — licence MIT. Les médias d'origine (© Gym visual) ne sont pas utilisés dans cette app.")
                    .font(.footnote)
                Link("github.com/hasaneyldrm/exercises-dataset",
                     destination: URL(string: "https://github.com/hasaneyldrm/exercises-dataset")!)
                    .font(.footnote)
            }

            Section("Photos d'exercices") {
                Text("Free Exercise DB — domaine public (Unlicense).")
                    .font(.footnote)
                Link("github.com/yuhonas/free-exercise-db",
                     destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!)
                    .font(.footnote)
            }

            Section("Circuits de course") {
                Text("Tracés générés à partir des données © les contributeurs OpenStreetMap, disponibles sous licence ODbL.")
                    .font(.footnote)
                Link("openstreetmap.org/copyright",
                     destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    .font(.footnote)
            }

            Section("Confidentialité") {
                Text("GymTracker ne collecte aucune donnée : entraînements, courses et profil restent sur cet appareil.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Licences et crédits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Onboarding au premier lancement

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("profileName") private var name = ""
    @AppStorage("profileHeightCm") private var heightCm = 175
    @AppStorage("profileWeightKg") private var weightKg = 70.0
    @AppStorage("profileSex") private var sexRaw = UserSex.unspecified.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                            .frame(width: 92, height: 92)
                            .background(
                                LinearGradient(colors: [.indigo, .purple],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                            )
                        Text("Bienvenue dans GymTracker")
                            .font(.title2.bold())
                        Text("Ces infos personnalisent ton accueil et tes stats. Elles restent 100 % sur ton appareil.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Ton prénom") {
                    TextField("Prénom", text: $name)
                }

                Section("À propos de toi") {
                    Picker("Sexe", selection: $sexRaw) {
                        ForEach(UserSex.allCases) { sex in
                            Text(sex.rawValue).tag(sex.rawValue)
                        }
                    }
                    Stepper("Taille : \(heightCm) cm", value: $heightCm, in: 120...230)
                    Stepper(String(format: "Poids : %.1f kg", weightKg),
                            value: $weightKg, in: 30...250, step: 0.5)
                }

                Section {
                    Button {
                        hasCompletedOnboarding = true
                    } label: {
                        Text("C'est parti 💪")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Modifiable à tout moment via l'icône profil de l'accueil.")
                }
            }
            .navigationTitle("Bienvenue")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profileName") private var name = ""
    @AppStorage("profileHeightCm") private var heightCm = 175
    @AppStorage("profileWeightKg") private var weightKg = 70.0
    @AppStorage("profileSex") private var sexRaw = UserSex.unspecified.rawValue

    private var bmi: Double? {
        guard heightCm > 0, weightKg > 0 else { return nil }
        let meters = Double(heightCm) / 100
        return weightKg / (meters * meters)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identité") {
                    TextField("Prénom (affiché sur l'accueil)", text: $name)
                    Picker("Sexe", selection: $sexRaw) {
                        ForEach(UserSex.allCases) { sex in
                            Text(sex.rawValue).tag(sex.rawValue)
                        }
                    }
                }

                Section("Mensurations") {
                    Stepper("Taille : \(heightCm) cm", value: $heightCm, in: 120...230)
                    Stepper(String(format: "Poids : %.1f kg", weightKg),
                            value: $weightKg, in: 30...250, step: 0.5)
                    if let bmi {
                        LabeledContent("IMC", value: String(format: "%.1f", bmi))
                    }
                }

                Section {
                    Text("Ces informations restent sur ton appareil — aucune n'est envoyée nulle part.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("À propos") {
                    LabeledContent("Version",
                                   value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    NavigationLink("Licences et crédits") { CreditsView() }
                }
            }
            .navigationTitle("Mon profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
