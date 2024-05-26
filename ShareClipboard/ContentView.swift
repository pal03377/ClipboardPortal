import SwiftUI
import UserNotifications

struct ContentView: View {
    @StateObject private var receiverStore = ReceiverStore()
    @State private var isChangeReceiverIdShown: Bool = false // Whether the input to change the receiver is shown
    @State private var receiverIdInputValue: String = ""
    @State private var receiverIdInputError: String? = nil // Error message for invalid receiver ID e.g. "Receiver ID must be a 8-digit number"
    @State private var isNotificationAllowed: Bool = false
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @Binding var pasteShortcutDisabledTemporarily: Bool // Disable clipboard-send shortcut to be able to paste a receiver ID temporarily
    @FocusState private var receiverIdInputFocused
    let updateTimer = Timer.publish(every: 4, tolerance: 2, on: .main, in: .common).autoconnect() // Timer to fetch new clipboard contents every Xs


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
                            .keyPressMacOS14(.return) {
                                Task { try await saveReceiverId() }
                                return true // Return if handled
                            }
                        Button { // Button to delete receiver ID
                            Task {
                                try? await receiverStore.delete()
                                isChangeReceiverIdShown = false
                                clipboardManager.sendErrorMessage = nil // Invalidate sending error message because it doesn't make much sense now
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
                VStack {
                    if let user = userStore.user {
                        // User loaded
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("You can receive clipboard contents.")
                        }
                        HStack {
                            Text("Connection code:")
                            Text(user.id).monospaced().copyContent(ClipboardContent(type: .text, content: user.id))
                            Button {} label: { Image(systemName: "doc.on.doc") }.copyContent(ClipboardContent(type: .text, content: user.id)) // Copy button
                            ShareLink(item: "Connect with me using this connection code: \(user.id)") // Share button
                        }
                        // Show clipboard receiving errors
                        if let receiveErrorMessage = clipboardManager.receiveErrorMessage {
                            Text(receiveErrorMessage)
                                .foregroundStyle(.red)
                        }
                    } else {
                        if let errorMsg = userStore.userLoadErrorMessage {
                            Text(errorMsg).foregroundStyle(.red) // Show error message
                            Button {
                                Task { await userStore.load() }
                            } label: { Text("Retry") }
                        } else {
                            // User still loading
                            ProgressView()
                        }
                    }
                }
                .task(id: userStore.user) { // Load user on change
                    // Load user on init and after it was deleted (using the "Reset user" menu entry
                    if userStore.user == nil {
                        Task { await userStore.load() }
                    }
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
                List(clipboardManager.clipboardHistory.reversed(), id: \.self) { historyEntry in
                    HStack {
                        Text(historyEntry.clipboardContent.content)
                            .lineLimit(4)
                            .truncationMode(.tail)
                        Spacer()
                        Button {} label: { Image(systemName: "doc.on.doc") }
                            .copyContent(historyEntry.clipboardContent)
                        if let _ = receiverStore.receiverId {
                            Button { // Resend button
                                Task {
                                    await clipboardManager.sendClipboardContent(content: historyEntry.clipboardContent)
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
        .task(id: isChangeReceiverIdShown) {
            self.pasteShortcutDisabledTemporarily = self.isChangeReceiverIdShown // Disable global paste shortcut while the receiver ID TextField is shown to be able to paste the receiver ID in the TextField
        }
        .task(id: receiverStore.receiverId) {
            // Update clipboardManager so that the ShareClipboardApp does not need to know the receiver ID itself
            self.clipboardManager.receiverId = self.receiverStore.receiverId
        }
        .onReceive(updateTimer) { _ in
            Task { await checkForNewClipboardContents() }
        }
    }
    
    func checkNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { // Update UI in main thread
                self.isNotificationAllowed = (settings.authorizationStatus == .authorized)
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
        clipboardManager.sendErrorMessage = nil // Invalidate sending error message because it doesn't make much sense now
    }
    
    // Check for new clipboard contents on the server
    func checkForNewClipboardContents() async {
        if let user = userStore.user {
            let isNewClipboardContent = await clipboardManager.checkForUpdates(user: user)
            if isNewClipboardContent { // New notification was found?
                // Create local notification to show it
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

#Preview {
    @State var pasteShortcutDisabledTemporarily = false
    return ContentView(pasteShortcutDisabledTemporarily: $pasteShortcutDisabledTemporarily)
        .environmentObject(UserStore())
        .environmentObject(ClipboardManager())
}
