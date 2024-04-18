import SwiftUI
import UserNotifications

struct ContentView: View {
    @StateObject private var receiverStore = ReceiverStore()
    @State private var isChangeReceiverIdShown: Bool = false // Whether the input to change the receiver is shown
    @State private var receiverIdInputValue: String = ""
    @State private var receiverIdInputError: String? = nil // Error message for invalid receiver ID e.g. "Receiver ID must be a 8-digit number"
    @EnvironmentObject private var deviceTokenStore: DeviceTokenStore
    @State private var isNotificationAllowed: Bool = false
    @StateObject private var userStore = UserStore()
    @State private var userLoadErrorMessage: String?
    @EnvironmentObject private var clipboardManager: ClipboardManager

    var body: some View {
        VStack {
            Text("Send your clipboard")
                .font(.largeTitle)
            VStack {
                if let receiverId = receiverStore.receiverId, !isChangeReceiverIdShown {
                    // Receiver ID exists and is not in change mode
                    HStack {
                        if clipboardManager.sending { ProgressView() } // Show loading spinner while sending clipboard contents
                        Text("Press")
                        Button {
                            Task {
                                await clipboardManager.sendClipboardContent()
                            }
                        } label: { Text("⌘+V") }
                        Text("to send to")
                        Text(receiverId).monospaced()
                        Button { isChangeReceiverIdShown = true } label: { Text("Edit") }
                    }
                    // Show clipboard sending errors
                    if let sendErrorMessage = clipboardManager.sendErrorMessage {
                        Text(sendErrorMessage)
                            .foregroundStyle(.red)
                    }
                } else {
                    // Change mode for receiver ID
                    HStack {
                        Text("Receiver ID:")
                        TextField("12345678", text: $receiverIdInputValue)
                            .frame(width: 100)
                            // Allow only numbers
                            .onReceive(receiverIdInputValue.publisher.collect()) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    receiverIdInputValue = String(filtered)
                                }
                            }
                        Button { // Button to delete receiver ID
                            Task {
                                try? await receiverStore.delete()
                                isChangeReceiverIdShown = false
                            }
                        } label: { Image(systemName: "trash") }
                        Button { // Button to save receiver ID
                            Task {
                                do {
                                    try await receiverStore.validate(receiverId: receiverIdInputValue)
                                    receiverIdInputError = nil
                                } catch {
                                    receiverIdInputError = error.localizedDescription
                                }
                                do {
                                    try await receiverStore.save(receiverId: receiverIdInputValue)
                                } catch {
                                    print("Error! \(error.localizedDescription)")
                                    fatalError(error.localizedDescription)
                                }
                                isChangeReceiverIdShown = false
                            }
                        } label: { Text("Save") }
                    }
                    .onAppear {
                        receiverIdInputValue = receiverStore.receiverId ?? "" // Initialize input value with existing value
                    }
                }
            }
            .task {
                await receiverStore.load()
            }
            
            Spacer()
                .frame(height: 32)
            
            Text("Receive other clipboard")
                .font(.largeTitle)
            if isNotificationAllowed {
                if let _ = deviceTokenStore.deviceToken {
                    VStack {
                        if let user = userStore.user {
                            // User loaded
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("You can receive clipboard contents.")
                            }
                            HStack {
                                Text("Connection code for your friend:")
                                Text(user.id).monospaced()
                                Button { // Copy button
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(user.id, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                ShareLink(item: "Connect with me using this connection code: \(user.id)") // Share button
                            }
                            Button {
                                Task {
                                    try await userStore.delete()
                                }
                            } label: { Text("Reset user") }
                        } else {
                            if let errorMsg = userLoadErrorMessage {
                                Text("Error while creating the user: \(errorMsg)")
                                Button {
                                    userLoadErrorMessage = nil
                                    Task { await loadUser() }
                                } label: { Text("Retry") }
                            } else {
                                // User still loading
                                ProgressView()
                            }
                        }
                    }
                    .task {
                        await loadUser()
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
            
            if !clipboardManager.clipboardHistory.isEmpty {
                Spacer()
                    .frame(height: 32)
                
                Text("History")
                    .font(.largeTitle)
                List(clipboardManager.clipboardHistory.reversed(), id: \.self) { content in
                    HStack {
                        Text(content)
                        Spacer()
                        Button { // Copy button
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        if let _ = receiverStore.receiverId {
                            Button { // Resend button
                                Task {
                                    await clipboardManager.sendClipboardContent(content: content)
                                }
                            } label: { Image(systemName: "paperplane") }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .border(Color.gray, width: 1)
            }
        }
        .padding()
        .onAppear {
            checkNotificationAuthorization()
        }
        .onChange(of: receiverStore.receiverId) {
            // Update clipboardManager so that the ShareClipboardApp does not need to know the receiver ID itself
            clipboardManager.receiverId = receiverStore.receiverId
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
    
    private func loadUser() async {
        guard let apnToken = deviceTokenStore.deviceToken else {
            DispatchQueue.main.async { self.userLoadErrorMessage = "There is no APN device token yet." } // Update UI in main thread
            return
        }
        do {
            try await userStore.load(apnToken: apnToken)
        } catch {
            DispatchQueue.main.async { self.userLoadErrorMessage = error.localizedDescription } // Show the error to the user. Update UI in main thread.
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DeviceTokenStore())
        .environmentObject(ClipboardManager())
}
