import SwiftUI
import UserNotifications

struct ContentView: View {
    @StateObject private var receiverStore = ReceiverStore()
    @State private var isChangeReceiverIdShown: Bool = false // Whether the input to change the receiver is shown
    @State private var receiverIdInputValue: String = ""
    @State private var receiverIdInputError: String? = nil // Error message for invalid receiver ID e.g. "Receiver ID must be a 8-digit number"
    @EnvironmentObject private var deviceTokenStore: DeviceTokenStore
    @State private var isNotificationAllowed: Bool = false
    @EnvironmentObject private var userStore: UserStore
    @State private var userLoadErrorMessage: String?
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @Binding var pasteShortcutDisabledTemporarily: Bool // Disable clipboard-send shortcut to be able to paste a receiver ID temporarily
    @FocusState private var receiverIdInputFocused

    var body: some View {
        VStack {
            Text("Send your clipboard")
                .font(.largeTitle)
            VStack {
                if let receiverId = receiverStore.receiverId, !isChangeReceiverIdShown {
                    // Receiver ID exists and is not in change mode
                    HStack {
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
                            .focusable()
                            .focused($receiverIdInputFocused)
                            .onAppear { receiverIdInputFocused = true } // Focus when TextField appears
                            // Allow only numbers
                            .onReceive(receiverIdInputValue.publisher.collect()) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    receiverIdInputValue = String(filtered)
                                }
                            }
                            // Save when pressing Enter
                            .onKeyPress(.return) {
                                Task { try await saveReceiverId() }
                                return .handled
                            }
                        Button { // Button to delete receiver ID
                            Task {
                                try? await receiverStore.delete()
                                isChangeReceiverIdShown = false
                            }
                        } label: { Image(systemName: "trash") }
                        Button { // Button to save receiver ID
                            Task { try await saveReceiverId() }
                        } label: { Text("Save") }
                    }
                    .onAppear {
                        receiverIdInputValue = receiverStore.receiverId ?? "" // Initialize input value with existing value
                    }
                }
            }
            .frame(height: 0) // Prevent jumping when the "Edit" button is pressed
            .task { await receiverStore.load() } // Load the receiver ID from local storage
            
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
                                Text("Connection code:")
                                Text(user.id).monospaced().copyContent(user.id)
                                Button {} label: { Image(systemName: "doc.on.doc") }.copyContent(user.id) // Copy button
                                ShareLink(item: "Connect with me using this connection code: \(user.id)") // Share button
                            }
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
                    .onChange(of: userStore.user, initial: true) {
                        // Load user on init and after it was deleted (using the "Reset user" menu entry
                        if userStore.user == nil {
                            Task { await loadUser() }
                        }
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
                            .lineLimit(4)
                            .truncationMode(.tail)
                        Spacer()
                        Button {} label: { Image(systemName: "doc.on.doc") }
                            .copyContent(content)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            // Dark loading overlay while sending clipboard contents
            if clipboardManager.sending {
                Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
                    .overlay {
                        ProgressView()
                    }
            } // Show loading spinner while sending clipboard contents
        }
        .onAppear {
            checkNotificationAuthorization()
        }
        .onChange(of: isChangeReceiverIdShown) {
            self.pasteShortcutDisabledTemporarily = self.isChangeReceiverIdShown // Disable global paste shortcut while the receiver ID TextField is shown to be able to paste the receiver ID in the TextField
        }
        .onChange(of: receiverStore.receiverId) {
            // Update clipboardManager so that the ShareClipboardApp does not need to know the receiver ID itself
            self.clipboardManager.receiverId = self.receiverStore.receiverId
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
    
    private func saveReceiverId() async throws {
        self.receiverIdInputError = receiverStore.validate(receiverId: receiverIdInputValue)
        if self.receiverIdInputError != nil { return } // Stop on validation error
        try await receiverStore.save(receiverId: receiverIdInputValue)
        isChangeReceiverIdShown = false
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
    @State var pasteShortcutDisabledTemporarily = false
    return ContentView(pasteShortcutDisabledTemporarily: $pasteShortcutDisabledTemporarily)
        .environmentObject(DeviceTokenStore())
        .environmentObject(UserStore())
        .environmentObject(ClipboardManager())
}
