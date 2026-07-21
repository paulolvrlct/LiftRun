import SwiftUI

// MARK: - Pluie de confettis (célébration façon Duolingo)

// Rendu Canvas piloté par l'horloge (TimelineView) : chaque frame est dessinée
// en fonction du temps écoulé — insensible aux transactions/animations SwiftUI,
// contrairement à la version déclarative qui pouvait être rendue directement
// dans son état final (confettis invisibles).
struct ConfettiView: View {
    private struct Particle {
        let x: CGFloat            // position horizontale relative (0...1)
        let delay: Double
        let duration: Double
        let color: Color
        let size: CGFloat
        let spin: Double
        let wobble: Double        // amplitude du zigzag horizontal
    }

    @State private var startDate = Date.now

    private let particles: [Particle] = {
        let palette: [Color] = [.indigo, .purple, .green, .orange, .teal, .pink, .yellow]
        return (0..<70).map { _ in
            Particle(
                x: .random(in: 0.02...0.98),
                delay: .random(in: 0...0.8),
                duration: .random(in: 2.0...3.4),
                color: palette.randomElement()!,
                size: .random(in: 7...13),
                spin: .random(in: 360...1080) * (Bool.random() ? 1 : -1),
                wobble: .random(in: 8...26)
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                for p in particles {
                    let progress = (elapsed - p.delay) / p.duration
                    guard progress > 0, progress < 1 else { continue }
                    let eased = progress * progress            // chute accélérée
                    let y = -30 + eased * (size.height + 60)
                    let x = p.x * size.width + sin(progress * .pi * 3) * p.wobble
                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .degrees(p.spin * progress))
                        layer.fill(
                            Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size * 0.28,
                                                     width: p.size, height: p.size * 0.55),
                                 cornerRadius: 2),
                            with: .color(p.color)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Tracé GPS stylisé (projection lat/lon → Path, dessin progressif via .trim)

struct RoutePathShape: Shape {
    let points: [(lat: Double, lon: Double)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let lats = points.map(\.lat), lons = points.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return path }

        // correction cos(latitude) pour conserver les proportions du tracé
        let cosLat = cos((minLat + maxLat) / 2 * .pi / 180)
        let spanX = max((maxLon - minLon) * cosLat, 1e-6)
        let spanY = max(maxLat - minLat, 1e-6)
        let scale = min(rect.width / spanX, rect.height / spanY)
        let offsetX = (rect.width - spanX * scale) / 2
        let offsetY = (rect.height - spanY * scale) / 2

        func project(_ p: (lat: Double, lon: Double)) -> CGPoint {
            CGPoint(x: rect.minX + offsetX + (p.lon - minLon) * cosLat * scale,
                    y: rect.minY + offsetY + (maxLat - p.lat) * scale)
        }

        path.move(to: project(points[0]))
        for point in points.dropFirst() {
            path.addLine(to: project(point))
        }
        return path
    }
}

// MARK: - Écran de fin de course (tracé qui se dessine + confettis)

struct RunCelebrationView: View {
    let run: RunSession
    @Environment(\.dismiss) private var dismiss

    @State private var appeared = false
    @State private var drawProgress: CGFloat = 0

    private var runBurnedKcal: Int {
        let stored = UserDefaults.standard.double(forKey: "profileWeightKg")
        return CalorieEstimator.runKcal(distanceKm: run.distanceKm,
                                        weightKg: stored > 0 ? stored : 70)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), .green.opacity(0.18), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ConfettiView()

            VStack(spacing: 20) {
                Text("Course terminée ! 🏃")
                    .font(.title.bold())
                Text("Ton tracé du jour :")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Group {
                    if run.routePoints.count > 1 {
                        RoutePathShape(points: run.routePoints)
                            .trim(from: 0, to: drawProgress)
                            .stroke(
                                LinearGradient(colors: [.green, .teal],
                                               startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                            )
                    } else {
                        Image(systemName: "figure.run")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                    }
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                HStack(spacing: 12) {
                    runTile(String(format: "%.2f km", run.distanceKm), "distance")
                    runTile(PaceFormatter.duration(run.durationSeconds), "durée")
                    runTile(PaceFormatter.string(secPerKm: run.averagePaceSecPerKm), "allure")
                    runTile("\(runBurnedKcal)", "kcal")
                }

                Button {
                    dismiss()
                } label: {
                    Text("Continuer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(24)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
                withAnimation(.easeInOut(duration: 2.2).delay(0.35)) { drawProgress = 1 }
            }
        }
    }

    private func runTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Écran de fin de séance

struct WorkoutCelebrationView: View {
    let setCount: Int
    let volume: Double
    let durationSeconds: Int
    var records: [PRResult] = []
    var onContinue: () -> Void

    @State private var appeared = false

    private var burnedKcal: Int {
        let stored = UserDefaults.standard.double(forKey: "profileWeightKg")
        return CalorieEstimator.workoutKcal(durationSeconds: durationSeconds,
                                            weightKg: stored > 0 ? stored : 70)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            ConfettiView()

            VStack(spacing: 18) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow)
                    .scaleEffect(appeared ? 1 : 0.2)
                    .rotationEffect(.degrees(appeared ? 0 : -20))

                Text(records.isEmpty ? "Séance terminée !" : "Séance record ! 🏆")
                    .font(.title.bold())

                Text(records.isEmpty ? "Belle séance, continue comme ça 🔥"
                                     : "Tu as battu \(records.count) record\(records.count > 1 ? "s" : "") 🔥")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(records.prefix(4)) { pr in
                            Label(pr.line, systemImage: "trophy.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                        if records.count > 4 {
                            Text("et \(records.count - 4) de plus…")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                HStack(spacing: 12) {
                    celebrationTile("\(setCount)", "séries")
                    celebrationTile(volume >= 1000 ? String(format: "%.1f t", volume / 1000)
                                                   : "\(Int(volume)) kg", "volume")
                    celebrationTile(PaceFormatter.duration(durationSeconds), "durée")
                    celebrationTile("\(burnedKcal)", "kcal")
                }

                Button {
                    onContinue()
                } label: {
                    Text("Continuer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
            .padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 28)
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.05)) {
                appeared = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func celebrationTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
