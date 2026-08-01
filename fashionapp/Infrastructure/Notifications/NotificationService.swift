import Foundation
import UserNotifications

final class LocalNotificationService: NotificationScheduling {
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
        content.title = "Today's outfit is ready"
        content.body = "Open Nook for weather-aware looks from your wardrobe."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily-outfit-reminder",
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}
