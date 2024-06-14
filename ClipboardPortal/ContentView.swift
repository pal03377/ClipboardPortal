import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var clipboardManager: ClipboardManager
    @State var isSettingsOpen = false
    let updateTimer = Timer.publish(every: 4, tolerance: 2, on: .main, in: .common).autoconnect() // Timer to fetch new clipboard contents every Xs

    var body: some View {
        ScrollView {
            VStack {
                CommandVView() {
                    Task { await clipboardManager.sendClipboardContent() }
                }
                .opacity(clipboardManager.sending ? 0.8 : 1)
                .overlay {
                    if clipboardManager.sending { ProgressView() } // Show loading spinner while sending clipboard contents
                }
                ClipboardHistoryListView(history: clipboardManager.clipboardHistory) { clipboardContent in
                    // (Re-)Send entry content
                    Task {
                        await clipboardManager.sendClipboardContent(content: clipboardContent)
                    }
                }
            }
            .padding()
            .scrollContentBackground(.hidden) // Transparent background instead of default darker background
        }
        .frame(minWidth: 400)
        .frame(minWidth: 300)
        .frame(minHeight: 120 + 32) // Cmd+V view + 1 row of history
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                StatusView(errorMessage: clipboardManager.sendErrorMessage ?? clipboardManager.receiveErrorMessage ?? userStore.userLoadErrorMessage ?? nil)
                Button {  isSettingsOpen = true } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $isSettingsOpen, arrowEdge: .top) {
                    SettingsView().padding()
                }
                .focusEffectDisabledMacOS14()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.1))
            .clipShape(.rect(topLeadingRadius: 4))
        }
        .task(id: clipboardManager.clipboardHistory) {
            Task {
                if let lastClipboardContent = clipboardManager.lastReceivedContent {
                    await userStore.updateLastReceivedClipboardContent(lastClipboardContent)
                }
            }
        }
        .task(id: settingsStore.settingsData.receiverId) {
            // Update clipboardManager so that the ClipboardPortalApp does not need to know the receiver ID itself
            self.clipboardManager.receiverId = self.settingsStore.settingsData.receiverId
        }
        .onReceive(updateTimer) { _ in
            Task { await checkForNewClipboardContents() }
        }
    }
    
    // Check for new clipboard contents on the server
    func checkForNewClipboardContents() async {
        guard let user = userStore.user else { return }
        let isNewClipboardContent = await clipboardManager.checkForUpdates(user: user)
        // Show notification (if wanted)
        guard settingsStore.settingsData.notificationsEnabled else { return } // Only continue is notifications are enabled
        if isNewClipboardContent, let clipboardContent = clipboardManager.clipboardHistory.last?.clipboardContent { // New notification was found?
            await showClipboardContentNotification(clipboardContent)
        }
    }
}

#Preview {
    return ContentView()
        .environmentObject(AppGlobals())
        .environmentObject(SettingsStore())
        .environmentObject(UserStore())
        .environmentObject(ClipboardManager())
}
