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
    }
    
    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false // Disable tabs window tabs
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
                .frame(minWidth: 400) // Min window width to now squeeze text
                .frame(width: 400) // Default width as small as possible
                .task { await UserStore.shared.load() } // Load user data
                .task { await SettingsStore.shared.load() } // Load settings
                .task(id: userStore.user?.id) { // Start new clipboard update check connection for new user
                    await ClipboardManager.shared.connectForUpdates()
                }
        }
        .handlesExternalEvents(matching: []) // No new window when opening custom URL scheme clipboardportal://something
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
}
