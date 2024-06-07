import UserNotifications

// Show notification about new clipboard content
func showClipboardContentNotification(_ clipboardContent: ClipboardContent) async {
    // Create local notification to show it
    let notificationContent = UNMutableNotificationContent()
    notificationContent.title = "Received Clipboard!"
    notificationContent.body = clipboardContent.content
    notificationContent.sound = UNNotificationSound.default
    // Trigger notification after 5 seconds (for example)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: trigger)
    try? await UNUserNotificationCenter.current().add(request)
}
