import SwiftUI
import UserNotifications

// TODO:
// - Rename to Clipboard Portal (and show cool Portal icon and maybe some default sound)
// - Global Shortcut for pasting
// - Fix notification check
// - Extend button click area to whole top
// - Make history not scrollable and instead show X entries and make whole UI scrollable
// - Send images and files
// - URL Schema for receiving friend code


// Reasons to fetch every Xs instead of using the Apple Notification Service APNs:
// - APNs was very hard to debug locally with a sandbox
// - The notifications were really unreliable, even with highest priority.
// - Notifications can still be prevented from being delivered because of energy consumption considerations and because of some screen recording software or so (AltTab, Rewind, ...)
// APNs has a content size limit of around 1000 characters, which is way too low for general clipboard contents

class AppDelegate: NSObject, NSApplicationDelegate {
    var clipboardManager = ClipboardManager()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
    }

    func application(_ application: NSApplication, open urls: [URL]) {
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
                        await clipboardManager.sendClipboardContent(content: ClipboardContent(type: ClipboardContentTypes(rawValue: type) ?? .text, content: content))
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
struct ClipboardFriendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var appGlobals = AppGlobals()
    @StateObject var userStore = UserStore()
    @StateObject var settingsStore = SettingsStore()
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
