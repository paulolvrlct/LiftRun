import SwiftUI
import SwiftData
import MapKit

struct RunningView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RunSession.date, order: .reverse) private var pastRuns: [RunSession]

    @StateObject private var tracker = RunTracker()
    @ObservedObject private var premium = PremiumStore.shared
    @State private var showActiveRun = false
    @State private var showPaywall = false
    @State private var selectedCircuit: RunCircuit?
    @State private var previewedCircuit: RunCircuit?
    @State private var celebratedRun: RunSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    startCard
                    if !CircuitLibrary.all.isEmpty { circuitsSection }
                    if !pastRuns.isEmpty { historySection }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Course")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(item: $previewedCircuit) { circuit in
                CircuitPreviewView(circuit: circuit,
                                   isSelected: selectedCircuit == circuit) {
                    toggleSelection(circuit)
                }
            }
            .fullScreenCover(isPresented: $showActiveRun) {
                ActiveRunView(tracker: tracker, circuit: selectedCircuit) { result in
                    if let result {
                        let run = RunSession(distanceMeters: result.distance,
                                             durationSeconds: result.duration,
                                             routeEncoded: result.route)
                        context.insert(run)
                        try? context.save()

                        // Enregistre la course dans Apple Santé
                        let weight = UserDefaults.standard.double(forKey: "profileWeightKg")
                        let kcal = CalorieEstimator.runKcal(distanceKm: run.distanceKm,
                                                            weightKg: weight > 0 ? weight : 70)
                        let start = run.date.addingTimeInterval(-TimeInterval(run.durationSeconds))
                        Task {
                            await HealthKitManager.shared.saveRun(
                                start: start, durationSeconds: run.durationSeconds,
                                kcal: kcal, distanceMeters: run.distanceMeters)
                        }

                        // laisse la vue de course se refermer avant la célébration
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            celebratedRun = run
                        }
                    }
                }
            }
            .fullScreenCover(item: $celebratedRun) { run in
                RunCelebrationView(run: run)
            }
            .onAppear { tracker.requestAuthorization() }
        }
    }

    private var startCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(LinearGradient(colors: [.green, .teal],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle())

            Text("Prêt à courir ?")
                .font(.title3.weight(.semibold))
            Text("Suivi GPS de ton allure, ta distance et ton tracé, visible sur l'écran verrouillé.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if tracker.authorizationDenied {
                Label("Localisation refusée : active-la dans Réglages pour le suivi GPS.",
                      systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button {
                tracker.start()
                showActiveRun = true
            } label: {
                Label("Démarrer la course", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            if let selectedCircuit {
                Label("Circuit : \(selectedCircuit.name)", systemImage: "map.fill")
                    .font(.caption)
                    .foregroundStyle(.teal)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    // MARK: Circuits préenregistrés (Premium)

    private var circuitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Circuits")
                    .font(.headline)
                if !premium.isPremium {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4)

            ForEach(CircuitLibrary.all) { circuit in
                HStack(spacing: 14) {
                    // Zone aperçu : ouvre la carte du tracé
                    Button {
                        previewedCircuit = circuit
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "map.fill")
                                .font(.title3)
                                .foregroundStyle(.teal)
                                .frame(width: 44, height: 44)
                                .background(Color.teal.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(circuit.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(String(format: "%.1f km · toucher pour l'aperçu", circuit.distanceKm))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    // Sélection directe
                    Button {
                        toggleSelection(circuit)
                    } label: {
                        Image(systemName: !premium.isPremium ? "lock.fill"
                              : selectedCircuit == circuit ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedCircuit == circuit ? .teal : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            }

            Text("Le circuit choisi s'affiche en pointillés sur la carte pendant ta course.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    private func toggleSelection(_ circuit: RunCircuit) {
        guard premium.isPremium else {
            // léger délai : laisse la sheet d'aperçu se fermer avant d'ouvrir le paywall
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showPaywall = true }
            return
        }
        selectedCircuit = selectedCircuit == circuit ? nil : circuit
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mes courses")
                .font(.headline)
                .padding(.leading, 4)
            ForEach(pastRuns) { run in
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    RunHistoryRow(run: run)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(run); try? context.save()
                    } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
        }
    }
}

// MARK: - Course en cours

struct ActiveRunView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tracker: RunTracker
    var circuit: RunCircuit? = nil
    var onFinish: ((distance: Double, duration: Int, route: String)?) -> Void

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showStopConfirm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) {
                UserAnnotation()
                // Calque du circuit préenregistré (tracé à suivre)
                if let circuit, circuit.coordinates.count > 1 {
                    MapPolyline(coordinates: circuit.coordinates)
                        .stroke(.teal.opacity(0.8),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [7, 7]))
                }
                if tracker.route.count > 1 {
                    MapPolyline(coordinates: tracker.route)
                        .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea()

            statsPanel
        }
        .alert("Terminer la course ?", isPresented: $showStopConfirm) {
            Button("Continuer", role: .cancel) {}
            Button("Terminer", role: .destructive) {
                let result = tracker.finish()
                onFinish(result)
                dismiss()
            }
        } message: {
            Text(tracker.distanceMeters > 20
                 ? "Distance : \(String(format: "%.2f", tracker.distanceMeters / 1000)) km"
                 : "Course trop courte, elle ne sera pas enregistrée.")
        }
    }

    private var statsPanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                stat(value: String(format: "%.2f", tracker.distanceMeters / 1000), unit: "km")
                divider
                stat(value: PaceFormatter.string(secPerKm: tracker.currentPaceSecPerKm)
                        .replacingOccurrences(of: "/km", with: ""), unit: "min/km")
                divider
                stat(value: PaceFormatter.duration(tracker.elapsedSeconds), unit: "durée")
            }

            HStack(spacing: 14) {
                Button {
                    tracker.togglePause()
                } label: {
                    Label(tracker.isPaused ? "Reprendre" : "Pause",
                          systemImage: tracker.isPaused ? "play.fill" : "pause.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(tracker.isPaused ? .green : .orange)

                Button {
                    showStopConfirm = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding()
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }

    private var divider: some View {
        Rectangle().fill(.secondary.opacity(0.2)).frame(width: 1, height: 40)
    }

    private func stat(value: String, unit: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Aperçu d'un circuit

struct CircuitPreviewView: View {
    let circuit: RunCircuit
    let isSelected: Bool
    var onToggleSelect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Map(initialPosition: .automatic) {
                    MapPolyline(coordinates: circuit.coordinates)
                        .stroke(.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    if let start = circuit.coordinates.first {
                        Marker("Départ / arrivée", systemImage: "flag.fill", coordinate: start)
                            .tint(.green)
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 12) {
                    infoTile("Distance", String(format: "%.1f km", circuit.distanceKm),
                             "point.topleft.down.to.point.bottomright.curvepath")
                    infoTile("Type", "Boucle", "arrow.triangle.2.circlepath")
                    infoTile("Points GPS", "\(circuit.coordinates.count)", "mappin.and.ellipse")
                }

                Button {
                    onToggleSelect()
                    dismiss()
                } label: {
                    Label(isSelected ? "Retirer ce circuit" : "Courir ce circuit",
                          systemImage: isSelected ? "xmark.circle" : "figure.run")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSelected ? .orange : .teal)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle(circuit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func infoTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(.teal)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Ligne d'historique

private struct RunHistoryRow: View {
    let run: RunSession

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.2f km", run.distanceKm))
                    .font(.headline.monospacedDigit())
                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(PaceFormatter.string(secPerKm: run.averagePaceSecPerKm))
                    .font(.subheadline.monospacedDigit())
                Text(PaceFormatter.duration(run.durationSeconds))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Détail d'une course (carte du tracé)

struct RunDetailView: View {
    let run: RunSession
    @State private var gpxURL: URL?

    private var coordinates: [CLLocationCoordinate2D] {
        run.routePoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if coordinates.count > 1 {
                    Map(initialPosition: .automatic) {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        if let start = coordinates.first {
                            Marker("Départ", systemImage: "flag.fill", coordinate: start).tint(.green)
                        }
                        if let end = coordinates.last {
                            Marker("Arrivée", systemImage: "flag.checkered", coordinate: end).tint(.red)
                        }
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                HStack(spacing: 12) {
                    metricTile("Distance", String(format: "%.2f km", run.distanceKm), "point.topleft.down.to.point.bottomright.curvepath")
                    metricTile("Durée", PaceFormatter.duration(run.durationSeconds), "clock")
                    metricTile("Allure", PaceFormatter.string(secPerKm: run.averagePaceSecPerKm), "speedometer")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(run.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { gpxURL = GPXExporter.exportFile(for: run) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let gpxURL {
                    ShareLink(item: gpxURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func metricTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(.green)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
