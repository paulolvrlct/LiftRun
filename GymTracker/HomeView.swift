import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \RunSession.date, order: .reverse) private var runs: [RunSession]

    @State private var activeTemplate: WorkoutTemplate?
    @State private var showLibrary = false
    @State private var showProfile = false
    @AppStorage("profileName") private var profileName = ""

    private var calendar: Calendar { Calendar.current }

    private var sessionsThisWeek: Int {
        sessions.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count
    }
    private var volumeThisMonth: Int {
        Int(sessions
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.totalVolume })
    }
    private var kmThisMonth: Double {
        runs.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.distanceKm }
    }
    /// Nombre de jours consécutifs (jusqu'à aujourd'hui) avec au moins une activité
    private var streak: Int {
        let days = Set((sessions.map(\.date) + runs.map(\.date)).map { calendar.startOfDay(for: $0) })
        var count = 0
        var day = calendar.startOfDay(for: .now)
        // Tolère l'absence d'activité aujourd'hui : on part d'hier si besoin
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private var greeting: String {
        let h = calendar.component(.hour, from: .now)
        switch h {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon aprèm"
        default: return "Bonsoir"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    statsGrid
                    NavigationLink {
                        NutritionView()
                    } label: {
                        NutritionHomeCard()
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        SupplementsView()
                    } label: {
                        SupplementsCard()
                    }
                    .buttonStyle(.plain)
                    quickStartSection
                    recentActivitySection
                    footerSignature
                }
                .padding()
            }
            .background(backgroundGradient)
            .navigationTitle("Accueil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Mon profil")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLibrary = true
                    } label: {
                        Image(systemName: "books.vertical.fill")
                    }
                    .accessibilityLabel("Bibliothèque d'exercices")
                }
            }
            .sheet(isPresented: $showLibrary) {
                ExerciseLibraryView()
            }
            .sheet(isPresented: $showProfile) {
                ProfileView()
            }
            .fullScreenCover(item: $activeTemplate) { template in
                ActiveWorkoutView(template: template)
            }
        }
    }

    // MARK: Signature

    private var footerSignature: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.caption)
            Text("Une app DevShield")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: Fond dégradé (base du rendu "liquid glass")

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemGroupedBackground), Color.brand.opacity(0.12), Color(.systemGroupedBackground)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profileName.isEmpty ? greeting + " 👋" : "\(greeting), \(profileName) 👋")
                .font(.largeTitle.weight(.bold))
            // le nombre de jours est déjà mis en avant dans la carte « streak » :
            // ici on garde un message d'encouragement sans répéter le chiffre
            Text(streak > 0
                 ? "Belle régularité, garde le rythme 🔥"
                 : "Prêt à t'y remettre aujourd'hui ?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Grille de stats

    @State private var statsAppeared = false

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            GlassStatCard(icon: "flame.fill", tint: .orange,
                          value: "\(sessionsThisWeek)", label: "séances cette semaine",
                          pulse: sessionsThisWeek > 0)
                .statEntrance(statsAppeared, index: 0)
            GlassStatCard(icon: "bolt.fill", tint: Color.brand,
                          value: "\(streak)", label: "jours de streak",
                          pulse: streak > 0)
                .statEntrance(statsAppeared, index: 1)
            GlassStatCard(icon: "scalemass.fill", tint: .purple,
                          value: volumeThisMonth >= 1000 ? String(format: "%.1ft", Double(volumeThisMonth) / 1000) : "\(volumeThisMonth)",
                          label: "volume ce mois (kg)")
                .statEntrance(statsAppeared, index: 2)
            GlassStatCard(icon: "figure.run", tint: .green,
                          value: String(format: "%.1f", kmThisMonth), label: "km ce mois")
                .statEntrance(statsAppeared, index: 3)
        }
        .onAppear {
            guard !statsAppeared else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { statsAppeared = true }
        }
    }

    // MARK: Démarrage rapide

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Démarrer une séance")
                .font(.headline)
                .padding(.leading, 4)

            if templates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "dumbbell")
                        .font(.title)
                        .foregroundStyle(Color.brand)
                    Text("Aucune séance type pour l'instant")
                        .font(.subheadline.weight(.medium))
                    Text("Crée ta première séance dans l'onglet Séances pour la lancer d'ici en un tap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .glassCard()
            }

            ForEach(templates) { template in
                Button {
                    activeTemplate = template
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: template.icon)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(LinearGradient(colors: [Color.brand, .purple],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.headline).foregroundStyle(.primary)
                            Text(template.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.brand)
                    }
                    .padding(14)
                    .glassCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Dernière activité (séance ou course, la plus récente)

    @ViewBuilder
    private var recentActivitySection: some View {
        let lastSession = sessions.first
        let lastRun = runs.first
        // on prend la plus récente des deux, tous types confondus
        let sessionIsNewer = (lastSession?.date ?? .distantPast) >= (lastRun?.date ?? .distantPast)

        if let session = lastSession, sessionIsNewer {
            recentCard(title: "Dernière activité", icon: "checkmark.seal.fill", tint: .green,
                       name: session.templateName, date: session.date,
                       trailing: "\(session.sets.count) séries")
        } else if let run = lastRun {
            recentCard(title: "Dernière activité", icon: "figure.run", tint: .green,
                       name: String(format: "Course · %.2f km", run.distanceKm), date: run.date,
                       trailing: PaceFormatter.duration(run.durationSeconds))
        }
    }

    private func recentCard(title: String, icon: String, tint: Color,
                            name: String, date: Date, trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.leading, 4)
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold))
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassCard()
        }
    }
}

// MARK: - Carte statistique en verre

private struct GlassStatCard: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String
    var pulse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: pulse)
            Text(value)
                // taille relative → suit les réglages d'accessibilité (Dynamic Type)
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(16)
        .glassCard()
    }
}

// Entrée en cascade des cartes de stats (scale + fondu décalés)
private extension View {
    func statEntrance(_ appeared: Bool, index: Int) -> some View {
        self
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.6)
                .delay(Double(index) * 0.08), value: appeared)
    }
}

// MARK: - Effet "liquid glass" réutilisable
// Base glassmorphism (Material) qui fonctionne sur iOS 17+.
// Sur iOS 26+, on applique en plus le vrai Liquid Glass (.glassEffect).

extension View {
    @ViewBuilder
    func glassCard() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }
}
