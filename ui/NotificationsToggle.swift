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
                checkNotificationAuthorization()
            }
        }
    }

    func checkNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { // Update UI in main thread
                self.isNotificationsAllowed = (settings.authorizationStatus == .authorized)
                self.settingsStore.settingsData.notificationsEnabled = self.isNotificationsAllowed
                Task { try await self.settingsStore.save() }
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
