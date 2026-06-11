import SwiftUI

struct ContentView: View {
    @StateObject private var userStore = UserStore.shared // Observe user store
    @StateObject private var settingsStore = SettingsStore.shared // Observe settings store
    @StateObject private var clipboardManager = ClipboardManager.shared // Observe changes to clipboard sending / receiving
    @State var isSettingsOpen = false
    @State private var isDropTargeted = false
    @State private var isHoveringWindow = false
    let updateTimer = Timer.publish(every: 4, tolerance: 2, on: .main, in: .common).autoconnect() // Timer to fetch new clipboard contents every Xs

    private var showHoverControls: Bool {
        isHoveringWindow || isSettingsOpen
    }

    var body: some View {
        GeometryReader { proxy in
            content(size: proxy.size)
        }
        .frame(minWidth: 200)
        .frame(minHeight: 125) // Cmd+V view plus room for bottom media controls
        .modifier(DropToSendModifier())
    }

    private func content(size: CGSize) -> some View {
        let topPadding = size.height < 200 ? 0.0 : 10.0
        let bottomPadding = size.height < 200 ? 2.5 : 10.0

        return ZStack {
            if size.height < 200 {
                mainContent(size: size)
                    .padding(.horizontal, 10)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
                    .padding(.bottom, settingsStore.settingsData.mediaControlsEnabled ? 32 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    mainContent(size: size)
                        .padding(.horizontal, 10)
                        .padding(.top, topPadding)
                        .padding(.bottom, bottomPadding)
                        .padding(.bottom, settingsStore.settingsData.mediaControlsEnabled ? 32 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .scrollContentBackground(.hidden) // Transparent background instead of default darker background
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHoveringWindow = hovering
            }
        }
        .overlay(alignment: .bottom) {
            if settingsStore.settingsData.mediaControlsEnabled && showHoverControls {
                MediaControlsView(width: size.width) { command in
                    Task { await clipboardManager.sendClipboardContent(.mediaCommand(command)) }
                }
                .padding(.bottom, 6)
                .transition(.opacity)
                .onHover { hovering in
                    if hovering { isHoveringWindow = true }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showHoverControls {
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
                    .padding(8)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.25))
                .clipShape(.rect(topLeadingRadius: 4))
                .onHover { hovering in
                    if hovering { isHoveringWindow = true }
                }
            }
        }
    }

    @ViewBuilder
    private func mainContent(size: CGSize) -> some View {
        VStack {
            CommandVView(onPress: {
                Task { await clipboardManager.sendClipboardContent() }
            }, minHeight: size.height < 200 ? 92 : 120)
            .opacity(clipboardManager.sending ? 0.8 : 1)
            .overlay {
                if clipboardManager.sending { ProgressView() } // Show loading spinner while sending clipboard contents
            }
            FriendRequestView()
            if size.height >= 260 {
                ClipboardHistoryListView(history: clipboardManager.clipboardHistory) { clipboardContent in
                    // (Re-)Send entry content
                    Task {
                        await clipboardManager.sendClipboardContent( clipboardContent)
                    }
                }
            }
        }
    }
}

#Preview {
    return ContentView()
}
