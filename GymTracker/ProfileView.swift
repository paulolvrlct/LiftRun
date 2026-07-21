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
                Text("Structure et instructions issues du dataset « exercises-dataset » © 2026 Hasan Emir Yıldırım, sous licence MIT. Les médias d'origine (© Gym visual) ne sont pas utilisés dans cette app.")
                    .font(.footnote)
                Link("github.com/hasaneyldrm/exercises-dataset",
                     destination: URL(string: "https://github.com/hasaneyldrm/exercises-dataset")!)
                    .font(.footnote)
            }

            Section("Photos d'exercices") {
                Text("Free Exercise DB, domaine public (Unlicense).")
                    .font(.footnote)
                Link("github.com/yuhonas/free-exercise-db",
                     destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!)
                    .font(.footnote)
            }

            Section("Base alimentaire") {
                Text("Valeurs nutritionnelles issues de la table CIQUAL 2020 © ANSES, licence ouverte Etalab.")
                    .font(.footnote)
                Link("ciqual.anses.fr",
                     destination: URL(string: "https://ciqual.anses.fr")!)
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
                Text("LiftRun ne collecte aucune donnée : entraînements, courses et profil restent sur cet appareil.")
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
    @AppStorage("profileAge") private var age = 25
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
                        Text("Bienvenue dans LiftRun")
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
                    Stepper("Âge : \(age) ans", value: $age, in: 13...100)
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
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage("profileName") private var name = ""
    @AppStorage("profileAge") private var age = 25
    @AppStorage("profileHeightCm") private var heightCm = 175
    @AppStorage("profileWeightKg") private var weightKg = 70.0
    @AppStorage("profileSex") private var sexRaw = UserSex.unspecified.rawValue

    // Rappels de séance
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderDays") private var reminderDaysRaw = ""      // ex : "2,4,6"
    @AppStorage("reminderHour") private var reminderHour = 18
    @AppStorage("reminderMinute") private var reminderMinute = 0
    // Thème (Premium)
    @AppStorage("accentTheme") private var accentRaw = AccentTheme.indigo.rawValue
    @State private var showPaywall = false

    private let weekdays: [(id: Int, short: String)] = [
        (2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")
    ]
    private var reminderDays: Set<Int> {
        Set(reminderDaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var bmi: Double? {
        guard heightCm > 0, weightKg > 0 else { return nil }
        let meters = Double(heightCm) / 100
        return weightKg / (meters * meters)
    }

    private func applyReminders() {
        if remindersEnabled {
            NotificationManager.shared.requestAuthorization()
            NotificationManager.shared.scheduleWeeklyReminders(
                weekdays: reminderDays, hour: reminderHour, minute: reminderMinute)
        } else {
            NotificationManager.shared.clearWeeklyReminders()
        }
    }

    private func toggleDay(_ id: Int) {
        var days = reminderDays
        if days.contains(id) { days.remove(id) } else { days.insert(id) }
        reminderDaysRaw = days.sorted().map(String.init).joined(separator: ",")
        applyReminders()
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
                    Stepper("Âge : \(age) ans", value: $age, in: 13...100)
                    Stepper("Taille : \(heightCm) cm", value: $heightCm, in: 120...230)
                    Stepper(String(format: "Poids : %.1f kg", weightKg),
                            value: $weightKg, in: 30...250, step: 0.5)
                    if let bmi {
                        LabeledContent("IMC", value: String(format: "%.1f", bmi))
                    }
                }

                Section {
                    Text("Ces informations restent sur ton appareil : aucune n'est envoyée nulle part.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Rappels de séance") {
                    Toggle("Me rappeler de m'entraîner", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { applyReminders() }
                    if remindersEnabled {
                        HStack(spacing: 6) {
                            ForEach(weekdays, id: \.id) { day in
                                let on = reminderDays.contains(day.id)
                                Button {
                                    toggleDay(day.id)
                                } label: {
                                    Text(day.short)
                                        .font(.footnote.weight(.semibold))
                                        .frame(width: 34, height: 34)
                                        .background(on ? Color.indigo : Color(.tertiarySystemFill),
                                                    in: Circle())
                                        .foregroundStyle(on ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        DatePicker("Heure",
                                   selection: Binding(
                                    get: {
                                        Calendar.current.date(from: DateComponents(
                                            hour: reminderHour, minute: reminderMinute)) ?? .now
                                    },
                                    set: {
                                        let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                                        reminderHour = c.hour ?? 18
                                        reminderMinute = c.minute ?? 0
                                        applyReminders()
                                    }),
                                   displayedComponents: .hourAndMinute)
                    }
                }

                Section("Apparence") {
                    if premium.isPremium {
                        Picker("Couleur d'accent", selection: $accentRaw) {
                            ForEach(AccentTheme.allCases) { theme in
                                Label {
                                    Text(theme.label)
                                } icon: {
                                    Image(systemName: "circle.fill").foregroundStyle(theme.color)
                                }
                                .tag(theme.rawValue)
                            }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Couleur d'accent (Premium)", systemImage: "paintpalette")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        WorkoutToolsView()
                    } label: {
                        Label("Outils (disques, export CSV)", systemImage: "wrench.and.screwdriver")
                    }
                }

                Section("À propos") {
                    LabeledContent("Version",
                                   value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Développeur", value: "DevShield")
                    NavigationLink("Licences et crédits") { CreditsView() }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
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
