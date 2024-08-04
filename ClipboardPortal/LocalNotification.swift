import UserNotifications

// Show notification about new clipboard content
func showClipboardContentNotification(_ content: ClipboardContent) async {
    guard SettingsStore.shared.settingsData.notificationsEnabled else { return } // Only send notifications if enabled
    // Create local notification to show it
    let notificationContent = UNMutableNotificationContent()
    notificationContent.title = "New clipboard \(content.typeDescription)" // e.g. "New clipboard text"
    notificationContent.body = content.description
    notificationContent.sound = !SettingsStore.shared.settingsData.receiveSoundEnabled ? UNNotificationSound.default : nil // No sounds if app plays own sounds
    // Trigger notification after 5 seconds (for example)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: trigger)
    try? await UNUserNotificationCenter.current().add(request)
}
