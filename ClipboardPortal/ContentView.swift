import SwiftUI

struct ContentView: View {
    @StateObject private var userStore = UserStore.shared // Observe user store
    @StateObject private var settingsStore = SettingsStore.shared // Observe settings store
    @StateObject private var clipboardManager = ClipboardManager.shared // Observe changes to clipboard sending / receiving
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
                        await clipboardManager.sendClipboardContent( clipboardContent)
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
                StatusView(connecting: clipboardManager.connecting, errorMessage: clipboardManager.sendErrorMessage ?? clipboardManager.receiveErrorMessage ?? userStore.userLoadErrorMessage ?? nil)
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
        .task(id: userStore.user?.id) { // Start new clipboard update check connection for new user
            clipboardManager.connectForUpdates()
        }
    }
}

#Preview {
    return ContentView()
}
