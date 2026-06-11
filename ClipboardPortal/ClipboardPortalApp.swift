import SwiftUI
import UserNotifications
// Third-party
import KeyboardShortcuts

// Ideas
// - Clipboard portal clears the file on the server after receiving? (To save me some space)
// - A history of previously entered IDs that is then accessible from a drop list to pick an ID again in future? Made more useful with a text entry field to add a note, tag or name to the ID?
// - Support for Windows + Android + iOS + Linux?

// Reasons to use a websocket connection instead of using the Apple Notification Service APNs:
// - APNs was very hard to debug locally with a sandbox
// - The notifications were really unreliable, even with highest priority.
// - Notifications can still be prevented from being delivered because of energy consumption considerations and because of some screen recording software or so (AltTab, Rewind, ...)
// - APNs has a content size limit of around 1000 characters, which is way too low for general clipboard contents
// - Fetching every X seconds was less satisfying. WebSockets are so fast!

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Handle global shortcut for pasting
        KeyboardShortcuts.onKeyDown(for: .sendToFriend) {
            Task { await ClipboardManager.shared.sendClipboardContent() } // Paste clipboard contents
        }
        KeyboardShortcuts.onKeyDown(for: .mediaVolumeDown) {
            Task { await Self.sendMediaCommandIfEnabled(.volumeDown) }
        }
        KeyboardShortcuts.onKeyDown(for: .mediaPreviousTrack) {
            Task { await Self.sendMediaCommandIfEnabled(.previousTrack) }
        }
        KeyboardShortcuts.onKeyDown(for: .mediaPlayPause) {
            Task { await Self.sendMediaCommandIfEnabled(.playPause) }
        }
        KeyboardShortcuts.onKeyDown(for: .mediaNextTrack) {
            Task { await Self.sendMediaCommandIfEnabled(.nextTrack) }
        }
        KeyboardShortcuts.onKeyDown(for: .mediaVolumeUp) {
            Task { await Self.sendMediaCommandIfEnabled(.volumeUp) }
        }
        // Register global internal app notifications to make Clipboard Portal sync of confetti possible :D
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("de.pschwind.Confetti.wasFired"), object: nil, queue: .main) { notification in // User is throwing confetti?
            print("Received global confetti notification")
            Task { await ClipboardManager.shared.sendClipboardContent(.confetti) } // Let the other person participate in the fun by sending the confetti over
        }
    }
    
    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false // Disable tabs window tabs
    }

    @MainActor
    private static func sendMediaCommandIfEnabled(_ command: MediaCommand) async {
        guard SettingsStore.shared.settingsData.mediaControlsEnabled else { return }
        await ClipboardManager.shared.sendClipboardContent(.mediaCommand(command))
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Handle app url e.g. clipboardportal://paste?content=Something
        for url in urls {
            handleIncomingURL(url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        print("Open URL \(url)")
        // Handle the URL here
        if url.scheme == "clipboardportal" {
            if url.host == "paste" {
                // Parse URL components to access query items
                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                      let queryItems = components.queryItems else {
                    print("Invalid URL or missing components")
                    return
                }
                let type = queryItems.first(where: { $0.name == "type" })?.value ?? "text"
                let content = queryItems.first(where: { $0.name == "content" })?.value
                if let content = content {
                    print("Type: \(type), Content: \(content)")
                    Task {
                        let clipboardContent: ClipboardContent? = switch type {
                        case "text": .text(content)
                        case "file": if let url = URL(string: content) { .file(url) } else { nil }
                        case "fileCollection": if let url = URL(string: content) { .fileCollection(url, []) } else { nil }
                        default: .text(content)
                        }
                        guard let clipboardContent else { return }
                        await ClipboardManager.shared.sendClipboardContent(clipboardContent)
                        print("Sent clipboard contents!")
                    }
                } else {
                    print("Wrong URL: Missing content GET param")
                }
            }
            else if url.host == "recover" { // Recover last received clipboard item by regex
                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                      let queryItems = components.queryItems else {
                    print("Invalid URL or missing components")
                    return
                }
                let regexString = queryItems.first(where: { $0.name == "regex" })?.value ?? ""
                Task {
                    await ClipboardManager.shared.recoverLastReceivedClipboardItem(matching: regexString)
                }
            }
        }
    }
}

// Global variables for the app
class AppGlobals: ObservableObject {
    static let shared = AppGlobals()
    
    @Published @MainActor var pasteShortcutDisabledTemporarily: Bool = false // Disable paste to clipboard-send to be able to paste a receiver ID temporarily
}

@main
struct ClipboardPortalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var appGlobals = AppGlobals.shared // Observe changes to change behavior in SwiftUI (enable / disable paste dynamically)
    @StateObject private var userStore = UserStore.shared // Observe user store
    private var updateTimer: Timer?
    
    var body: some Scene {
        Window("Clipboard Portal", id: "main") {
            ContentView()
                .frame(minWidth: 200)
                .background(MainWindowConfigurationView(titleVisibilityThreshold: 300))
                .task { await UserStore.shared.load() } // Load user data
                .task { await SettingsStore.shared.load() } // Load settings
                .task(id: userStore.user?.id) { // Start new clipboard update check connection for new user
                    ClipboardManager.shared.connectForUpdates()
                }
            
            /* For later: Hide window and only show button
                .background(Color.clear) // Transparentes Fenster
                .edgesIgnoringSafeArea(.all) // Keine Ränder
                .onAppear {
                    configureWindow()
                }
                .gesture(WindowDragGesture())
             */
        }
        .handlesExternalEvents(matching: []) // No new window when opening custom URL scheme clipboardportal://something
        .defaultSize(width: 400, height: 260)
        .windowResizability(.contentSize)
        Window("More Settings", id: "more-settings") {
            MoreSettingsView()
                .padding()
        }
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: CommandGroupPlacement.newItem) {}
            if !appGlobals.pasteShortcutDisabledTemporarily {
                CommandGroup(replacing: .pasteboard) {
                    Button {
                        Task { await ClipboardManager.shared.sendClipboardContent() }
                    } label: { Text("Paste") }
                        .keyboardShortcut("v", modifiers: [.command])
                }
            }
            CommandGroup(after: .newItem) {
                Button {
                    Task {
                        await UserStore.shared.delete()
                        await UserStore.shared.load() // Reload user data
                        SettingsStore.shared.settingsData.receiverId = "" // Clear receiving user because that's less confusing
                        try? await SettingsStore.shared.save()
                    }
                } label: { Text("Reset user") }
                Button {
                    ClipboardManager.shared.clipboardHistory = []
                } label: { Text("Clear history") }
            }
        }
    }
    
    // For later
    // /// Konfiguriert das Fenster für fensterlosen Betrieb und "immer on top"
    // private func configureWindow() {
    //     DispatchQueue.main.async {
    //         if let window = NSApplication.shared.windows.first {
    //             window.titleVisibility = .hidden // Titel ausblenden
    //             window.titlebarAppearsTransparent = true // Titelbar transparent machen
    //             window.isOpaque = false // Fensterinhalt transparent
    //             window.backgroundColor = .clear // Hintergrundfarbe auf transparent setzen
    //             window.hasShadow = false // Schatten entfernen
    //             window.styleMask.remove(.resizable) // Größenänderung deaktivieren
    //             window.styleMask.remove(.titled) // Titelbar entfernen
    //             window.isMovableByWindowBackground = true // Bewegung per Hintergrund
    //             window.level = .floating // Fenster immer im Vordergrund
    //         }
    //     }
    // }
}

private struct MainWindowConfigurationView: NSViewRepresentable {
    var titleVisibilityThreshold: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(titleVisibilityThreshold: titleVisibilityThreshold)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.titleVisibilityThreshold = titleVisibilityThreshold
        DispatchQueue.main.async {
            context.coordinator.configureWindow(for: nsView)
        }
    }

    final class Coordinator {
        var titleVisibilityThreshold: CGFloat
        private weak var configuredWindow: NSWindow?
        private var resizeObserver: NSObjectProtocol?

        init(titleVisibilityThreshold: CGFloat) {
            self.titleVisibilityThreshold = titleVisibilityThreshold
        }

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }

        func configureWindow(for view: NSView) {
            guard let window = view.window else { return }

            if configuredWindow !== window {
                configuredWindow = window
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.collectionBehavior.remove(.fullScreenPrimary)

                if let resizeObserver {
                    NotificationCenter.default.removeObserver(resizeObserver)
                }
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.updateTitleVisibility(for: window)
                }
            }

            updateTitleVisibility(for: window)
        }

        private func updateTitleVisibility(for window: NSWindow) {
            let isCompact = window.frame.width < titleVisibilityThreshold
            window.titleVisibility = isCompact ? .hidden : .visible
            window.standardWindowButton(.miniaturizeButton)?.isHidden = isCompact
        }
    }
}
