import Foundation
import UserNotifications

/// Notifications locales — fonctionnent sur compte gratuit, sans serveur.
/// (Le push distant / APNs nécessite un compte payant + backend.)
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let restID = "rest-timer-finished"

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("Notifications autorisées : \(granted)")
        }
    }

    /// Notifie l'utilisateur à la fin du temps de repos (utile si l'app est en arrière-plan).
    func scheduleRestEnd(after seconds: Int, exerciseName: String) {
        cancelRestEnd()
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Repos terminé 💪"
        content.body = "C'est reparti ! \(exerciseName), série suivante."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: restID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelRestEnd() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restID])
    }

    /// Rappel de séance à une date donnée (optionnel, ex : « demain 18h »).
    func scheduleWorkoutReminder(at date: Date, title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Séance prévue"
        content.body = title
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "reminder-\(date.timeIntervalSince1970)",
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private let weeklyPrefix = "weekly-workout-"

    /// Programme des rappels hebdomadaires récurrents aux jours choisis.
    /// weekdays : 1 = dimanche … 7 = samedi (convention Apple).
    func scheduleWeeklyReminders(weekdays: Set<Int>, hour: Int, minute: Int) {
        clearWeeklyReminders()
        guard !weekdays.isEmpty else { return }
        for weekday in weekdays {
            let content = UNMutableNotificationContent()
            content.title = "C'est l'heure de bouger 💪"
            content.body = "Ta séance t'attend dans LiftRun."
            content.sound = .default

            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: "\(weeklyPrefix)\(weekday)",
                                                content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func clearWeeklyReminders() {
        let ids = (1...7).map { "\(weeklyPrefix)\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
