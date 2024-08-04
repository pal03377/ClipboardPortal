import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsStore = SettingsStore.shared // Observe changes to settings
    @StateObject private var userStore = UserStore.shared // Observe changes to user
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
                            Text(user.id).monospaced().copyContent(.text(user.id))
                                .gridColumnAlignment(.leading)
                                .padding(.leading, 4) // Align text with friend code input text
                        } else { ProgressView().scaleEffect(x: 0.5, y: 0.5, anchor: .center) } // User loading
                    }
                    // Column right
                    Group {
                        if let user = userStore.user {
                            // ShareLink(item: "Connect with me using this connection code: \(user.id)") // Share button
                            Button {} label: { Image(systemName: "doc.on.doc") }
                                .copyContent(.text(user.id))
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
                            AppGlobals.shared.pasteShortcutDisabledTemporarily = self.receiverIdInputFocused
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
            Spacer().frame(height: 8)
            GlobalShortcutView()
            NotificationsToggleView()
            Toggle(isOn: $settingsStore.settingsData.sendSoundEnabled) {
                Text("Sound when sending")
            }.task(id: settingsStore.settingsData.sendSoundEnabled) {
                Task { try await settingsStore.save() }
            }
            Toggle(isOn: $settingsStore.settingsData.receiveSoundEnabled) {
                Text("Sound when receiving")
            }.task(id: settingsStore.settingsData.receiveSoundEnabled) {
                Task { try await settingsStore.save() }
            }
        }
        .frame(width: 200)
    }
}

#Preview {
    return SettingsView()
        .padding()
        .onAppear {
            UserStore.shared.user = User(id: "12345678", secret: "", lastReceiveDate: nil)
            SettingsStore.shared.settingsData.receiverId = "87654321"
        }
}
