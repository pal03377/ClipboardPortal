import SwiftUI
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var deviceTokenStore: DeviceTokenStore
    @State private var isNotificationAllowed: Bool = false

    var body: some View {
        VStack {
            Text("Send your clipboard")
                .font(.largeTitle)
            Text("Press ⌘+V to send")
            Spacer()
                .frame(height: 32)
            Text("Receive other clipboard")
                .font(.largeTitle)
            if isNotificationAllowed {
                Text("You can receive clipboard contents. Send your friend the token to connect.")
                if let token = deviceTokenStore.deviceToken {
                    HStack {
                        Text("Token: \(token)")
                        ShareLink("Send to friend", item: token)
                    }
                } else if let error = deviceTokenStore.registrationError {
                    Text("Error: \(error.localizedDescription)")
                    Button {
                        registerForPushNotifications()
                    } label: { Text("Retry") }
                }
            } else {
                Button("Enable receiving clipboard") {
                    registerForPushNotifications()
                }
            }
        }
        .padding()
        .onAppear {
            checkNotificationAuthorization()
        }
    }
    
    func checkNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isNotificationAllowed = (settings.authorizationStatus == .authorized)
                if self.isNotificationAllowed && deviceTokenStore.deviceToken == nil {
                    DispatchQueue.main.async {
                        print("Registering...")
                        NSApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
    }
    
    func registerForPushNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    self.isNotificationAllowed = granted
                }
                print("Permission granted: \(granted)")
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(DeviceTokenStore())
}
