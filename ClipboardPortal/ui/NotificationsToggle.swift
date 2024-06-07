import SwiftUI
import UserNotifications

struct NotificationsToggle: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var isNotificationsAllowed: Bool = false

    var body: some View {
        Toggle(isOn: $settingsStore.settingsData.notificationsEnabled) {
            Text("Notify when receiving")
        }
        .task(id: settingsStore.settingsData.notificationsEnabled) {
            if settingsStore.settingsData.notificationsEnabled {
                checkNotificationAuthorization() // Check if permission was already granted
            }
        }
    }

    func checkNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { // Update UI in main thread
                self.isNotificationsAllowed = (settings.authorizationStatus == .authorized)
                // Request permission if needed
                if !self.isNotificationsAllowed && self.settingsStore.settingsData.notificationsEnabled { // Not yet allowed but wanted?
                    registerForPushNotifications() // Request notifications permission
                }
            }
        }
    }

    func registerForPushNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    settingsStore.settingsData.notificationsEnabled = granted
                    Task { try await self.settingsStore.save() }
                }
                print("Permission granted: \(granted)")
            }
    }
}

#Preview {
    NotificationsToggle()
        .padding()
}
