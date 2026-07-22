import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var premium = PremiumStore.shared
    @State private var selection = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("accentTheme") private var accentRaw = AccentTheme.indigo.rawValue

    private var accent: Color {
        // le thème n'est appliqué qu'aux abonnés Premium
        guard premium.isPremium, let t = AccentTheme(rawValue: accentRaw) else { return .indigo }
        return t.color
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(0)

            TemplatesView()
                .tabItem { Label("Séances", systemImage: "dumbbell.fill") }
                .tag(1)

            RunningView()
                .tabItem { Label("Course", systemImage: "figure.run") }
                .tag(2)

            HistoryView()
                .tabItem { Label("Calendrier", systemImage: "calendar") }
                .tag(3)

            ProgressChartsView()
                .tabItem { Label("Progression", systemImage: "chart.xyaxis.line") }
                .tag(4)
        }
        .tint(accent)
        // Premier lancement : demande prénom / taille / poids / sexe
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { shown in if !shown { hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
        }
        .onAppear {
            NutritionPlanner.publishForWidget(context: context)
            // Les permissions ne sont plus demandées en bloc au lancement :
            // - notifications → au 1er repos chronométré (RestTimerModel) et via le toggle Rappels
            // - Santé → une fois l'onboarding passé, pour l'export de l'historique
            if hasCompletedOnboarding {
                Task { await HealthKitManager.shared.backfillIfNeeded(context: context) }
            }
        }
        // Lien profond depuis le widget raccourci (gymtracker://run)
        .onOpenURL { url in
            if url.scheme == "gymtracker", url.host == "run" {
                selection = 2
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [WorkoutTemplate.self, WorkoutSession.self], inMemory: true)
}
