import SwiftUI
import UserNotifications
// Third-party
import KeyboardShortcuts


// Reasons to fetch every Xs instead of using the Apple Notification Service APNs:
// - APNs was very hard to debug locally with a sandbox
// - The notifications were really unreliable, even with highest priority.
// - Notifications can still be prevented from being delivered because of energy consumption considerations and because of some screen recording software or so (AltTab, Rewind, ...)
// APNs has a content size limit of around 1000 characters, which is way too low for general clipboard contents

class AppDelegate: NSObject, NSApplicationDelegate {
    var clipboardManager = ClipboardManager()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Handle global shortcut for pasting
        KeyboardShortcuts.onKeyDown(for: .sendToFriend) { [self] in
            Task { await clipboardManager.sendClipboardContent() } // Paste clipboard contents
        }
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
                        await clipboardManager.sendClipboardContent(clipboardContent)
                        print("Sent clipboard contents!")
                    }
                } else {
                    print("Wrong URL: Missing content GET param")
                }
            }
        }
    }
}

class AppGlobals: ObservableObject {
    @Published var pasteShortcutDisabledTemporarily: Bool = false // Disable paste to clipboard-send to be able to paste a receiver ID temporarily
}

@main
struct ClipboardPortalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var appGlobals = AppGlobals()
    @StateObject var userStore = UserStore()
    @StateObject var settingsStore = SettingsStore.shared
    private var updateTimer: Timer?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appGlobals)
                .environmentObject(userStore)
                .environmentObject(settingsStore)
                .environmentObject(appDelegate.clipboardManager)
                .frame(minWidth: 400) // Min window width to now squeeze text
                .task { await userStore.load() } // Load user data
                .task { await settingsStore.load() } // Load settings
        }
        .handlesExternalEvents(matching: []) // No new window when opening custom URL scheme clipboardportal://something
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
            if !appGlobals.pasteShortcutDisabledTemporarily {
                CommandGroup(replacing: .pasteboard) {
                    Button {
                        Task {
                            await appDelegate.clipboardManager.sendClipboardContent()
                        }
                    } label: { Text("Paste") }
                        .keyboardShortcut("v", modifiers: [.command])
                }
            }
            CommandGroup(after: .newItem) {
                Button {
                    Task {
                        await userStore.delete()
                        await userStore.load() // Reload user data
                    }
                } label: { Text("Reset user") }
            }
        }
    }
}
