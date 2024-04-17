import SwiftUI
import AppKit


class DeviceTokenStore: ObservableObject {
    @Published var deviceToken: String?
    @Published var registrationError: Error?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var deviceTokenStore = DeviceTokenStore()
    
    func application(
      _ application: NSApplication,
      didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        self.deviceTokenStore.deviceToken = token
    }
    
    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register: \(error)")
        deviceTokenStore.registrationError = error
    }
}


@main
struct ShareClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.deviceTokenStore)
        }
    }
}
