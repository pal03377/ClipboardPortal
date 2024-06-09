import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appGlobals: AppGlobals
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var userStore: UserStore
    @State private var isFriendsCodePopupOpen = false
    @FocusState private var receiverIdInputFocused
    
    var body: some View {
        VStack(alignment: .leading) {
            Grid {
                GridRow {
                    // Column left
                    Text("My code").gridColumnAlignment(.leading)
                    // Column center
                    Group {
                        if let user = userStore.user { // User available?
                            Text(user.id).monospaced().copyContent(ClipboardContent(type: .text, content: user.id))
                        } else { ProgressView().scaleEffect(x: 0.5, y: 0.5, anchor: .center) } // User loading
                    }
                    // Column right
                    Group {
                        if let user = userStore.user {
                            // ShareLink(item: "Connect with me using this connection code: \(user.id)") // Share button
                            Button {} label: { Image(systemName: "doc.on.doc") }
                                .copyContent(ClipboardContent(type: .text, content: user.id))
                        } else { Group {} }
                    }
                }
                GridRow {
                    // Column left
                    Text("Friend's code").gridColumnAlignment(.leading)
                    // Column center
                    TextField("????????", text: $settingsStore.settingsData.receiverId, onEditingChanged: { _ in
                        Task { try await settingsStore.save() }
                    }).monospaced()
                        .focused($receiverIdInputFocused)
                        // Allow only numbers
                        .onReceive(settingsStore.settingsData.receiverId.publisher.collect()) { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                settingsStore.settingsData.receiverId = String(filtered)
                            }
                        }
                        // Save when pressing Enter
                        .keyPressMacOS14(.return) {
                            Task { try await settingsStore.save() }
                            return true // Return that event was handled
                        }
                        // Disable global paste shortcut while the receiver ID TextField is shown to be able to paste the receiver ID in the TextField
                        .task(id: receiverIdInputFocused) {
                            appGlobals.pasteShortcutDisabledTemporarily = self.receiverIdInputFocused
                        }
                    // Column right
                    Button { isFriendsCodePopupOpen = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $isFriendsCodePopupOpen) {
                        Text("Enter your friend's 8-digit code here to paste into their clipboard.")
                            .padding()
                    }
                }
            }
            Divider()
            NotificationsToggleView()
        }
    }
}

#Preview {
    SettingsView()
        .padding()
        .environmentObject(AppGlobals())
        .environmentObject(SettingsStore())
        .environmentObject(UserStore())
}
