import SwiftUI
import UserNotifications

/// Dedicated notifications preferences screen (daily outfit / laundry reminder).
struct NotificationsSettingsView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.dailyOutfitReminderEnabled },
                    set: { viewModel.dailyOutfitReminderEnabled = $0 }
                )) {
                    Label(
                        NSLocalizedString("Daily reminder", comment: ""),
                        systemImage: "bell.badge"
                    )
                }

                if viewModel.dailyOutfitReminderEnabled {
                    Picker(
                        NSLocalizedString("Reminder time", comment: ""),
                        selection: Binding(
                            get: { viewModel.dailyOutfitReminderHour },
                            set: { viewModel.dailyOutfitReminderHour = $0 }
                        )
                    ) {
                        ForEach(Self.reminderHours, id: \.self) { hour in
                            Text(Self.timeLabel(for: hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text(NSLocalizedString("Reminders", comment: "Notifications section"))
            } footer: {
                Text(NSLocalizedString(
                    "Nook can remind you once a day to check today’s outfit, events, or laundry. Nook never sends marketing messages.",
                    comment: "Notifications screen footer"
                ))
            }

            if authorizationStatus == .denied {
                Section {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label(
                            NSLocalizedString("Open Settings", comment: "Open iOS Settings for notifications"),
                            systemImage: "gear"
                        )
                    }
                } footer: {
                    Text(NSLocalizedString(
                        "Notifications are turned off for Nook in iOS Settings. Enable them to receive the daily reminder.",
                        comment: "Permission denied footer"
                    ))
                }
            }

            Section {
                labeledRow(
                    title: NSLocalizedString("Outfit check-in", comment: ""),
                    detail: NSLocalizedString(
                        "A gentle nudge to plan what to wear.",
                        comment: "Notification type detail"
                    ),
                    systemImage: "tshirt"
                )
                labeledRow(
                    title: NSLocalizedString("Events & laundry", comment: ""),
                    detail: NSLocalizedString(
                        "Same reminder covers calendar plans and pieces that need a wash.",
                        comment: "Notification type detail"
                    ),
                    systemImage: "calendar"
                )
            } header: {
                Text(NSLocalizedString("What you’ll get", comment: "Notifications info header"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .nookSafeScreenInsets()
        .nookScreenBackground()
        .navigationTitle(NSLocalizedString("Notifications", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthorizationStatus() }
        .onChange(of: viewModel.dailyOutfitReminderEnabled) { _, _ in
            Task { await refreshAuthorizationStatus() }
        }
    }

    private static let reminderHours = [7, 8, 9, 10, 12, 18]

    private static func timeLabel(for hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display):00 \(period)"
    }

    private func labeledRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(AppColors.olive)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            authorizationStatus = settings.authorizationStatus
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
