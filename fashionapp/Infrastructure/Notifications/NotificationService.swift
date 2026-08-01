import Foundation
import UserNotifications

final class LocalNotificationService: NotificationScheduling {
    static let dailyOutfitReminderID = "daily-outfit-reminder"

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleDailyOutfitReminder(at dateComponents: DateComponents) async throws {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("What’s the plan today?", comment: "Daily reminder title")
        content.body = NSLocalizedString(
            "Open Nook to check today’s outfit, events, or laundry.",
            comment: "Daily reminder body"
        )
        content.sound = .default

        var components = DateComponents()
        components.hour = dateComponents.hour ?? 8
        components.minute = dateComponents.minute ?? 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.dailyOutfitReminderID,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyOutfitReminderID])
        try await center.add(request)
    }

    func cancelDailyOutfitReminder() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.dailyOutfitReminderID])
    }
}
