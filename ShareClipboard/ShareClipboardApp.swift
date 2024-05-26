import SwiftUI
import AppKit
import UserNotifications


class DeviceTokenStore: ObservableObject {
    @Published var deviceToken: String?
    @Published var registrationError: Error?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var deviceTokenStore = DeviceTokenStore()
    var userStore = UserStore()
    var clipboardManager = ClipboardManager()
    var checkNewClipboardTimer: Timer?
    
    // Handle APNs notification service registration event
    func application(
      _ application: NSApplication,
      didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        self.deviceTokenStore.deviceToken = token
    }
    
    // Handle APNs notification service registration error
    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register: \(error)")
        deviceTokenStore.registrationError = error
    }
    
    // Handle incoming APNs notifications to write the new clipboard contents
    struct ClipboardPayload: Codable {
        var clipboardContent: ClipboardContent
        var date: Date
    }
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        print("Received remote notification: \(userInfo)")
        if let clipboardContent = userInfo["clipboardContent"] as? ClipboardContent {
            Task {
                await clipboardManager.receiveClipboardContent(clipboardContent, user: userStore.user)
            }
        } else {
            print("No clipboard data found in the notification payload \(userInfo)")
        }
    }
    
    // Start timer to check for new clipboard contents periodically because APNs is not reliable enough
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Start timer to check for clipboard contents every X seconds
        checkNewClipboardTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(checkForNewClipboardContents), userInfo: nil, repeats: true)
    }
    // Terminate timer when app terminates
    func applicationWillTerminate(_ aNotification: Notification) {
        checkNewClipboardTimer?.invalidate()
    }
    // Check for new clipboard contents on the server
    @objc func checkForNewClipboardContents() {
        Task {
            if let user = userStore.user {
                let isNewNotification = await clipboardManager.checkForUpdates(user: user)
                if isNewNotification { // New notification was found before APNs notification reached this client?
                    // Create local notification to show it immediately
                    let content = UNMutableNotificationContent()
                    content.title = "Received Clipboard!"
                    content.body = clipboardManager.clipboardHistory.last?.clipboardContent.content ?? ""
                    content.sound = UNNotificationSound.default
                    // Trigger notification after 5 seconds (for example)
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
                    try? await UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }
}


@main
struct ShareClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var pasteShortcutDisabledTemporarily: Bool = false // Disable paste to clipboard-send to be able to paste a receiver ID temporarily
    
    var body: some Scene {
        WindowGroup {
            ContentView(pasteShortcutDisabledTemporarily: $pasteShortcutDisabledTemporarily)
                .environmentObject(appDelegate.deviceTokenStore)
                .environmentObject(appDelegate.userStore)
                .environmentObject(appDelegate.clipboardManager)
                .frame(minWidth: 400) // Min window width to now squeeze text
        }
        .commands {
            SidebarCommands()
            if !pasteShortcutDisabledTemporarily {
                CommandGroup(replacing: .pasteboard) {
                    Button {
                        Task {
                            await appDelegate.clipboardManager.sendClipboardContent()
                        }
                    } label: { Text("Paste") }
                        .keyboardShortcut("v", modifiers: [.command])
                }
            }
            CommandGroup(after: .newItem) {
                Button {
                    Task {
                        await appDelegate.userStore.delete()
                    }
                } label: { Text("Reset user") }
            }
        }
    }
}
