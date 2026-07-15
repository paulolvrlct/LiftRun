import WidgetKit
import SwiftUI

// Point d'entrée de la widget extension.
// Regroupe les Live Activities (timer de repos + course) et les widgets d'écran d'accueil.
@main
struct GymTrackerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
        RunLiveActivity()
        StreakWidget()
        VolumeChartWidget()
        RunShortcutWidget()
    }
}
