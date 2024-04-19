import SwiftUI
import AppKit


class DeviceTokenStore: ObservableObject {
    @Published var deviceToken: String?
    @Published var registrationError: Error?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var deviceTokenStore = DeviceTokenStore()
    var clipboardManager = ClipboardManager()
    
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
        var clipboardContent: String
    }
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        print("Received remote notification: \(userInfo)")
        if let clipboardContent = userInfo["clipboardContent"] as? String {
            clipboardManager.receiveClipboardContent(clipboardContent)
        } else {
            print("No clipboard data found in the notification payload \(userInfo)")
        }
    }
}


@main
struct ShareClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.deviceTokenStore)
                .environmentObject(appDelegate.clipboardManager)
        }
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .pasteboard) {
                Button {
                    Task {
                        await appDelegate.clipboardManager.sendClipboardContent()
                    }
                } label: { Text("Paste") }
                    .keyboardShortcut("v", modifiers: [.command])
            }
        }
    }
}
