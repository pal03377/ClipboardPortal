import SwiftUI
import UserNotifications

// TODO:
// - Send images and files
// - URL Schema for receiving friend code
// - URL Schema for Live Share (send URL directly to app)


// Reasons to fetch every Xs instead of using the Apple Notification Service APNs:
// - APNs was very hard to debug locally with a sandbox
// - The notifications were really unreliable, even with highest priority.
// - Notifications can still be prevented from being delivered because of energy consumption considerations and because of some screen recording software or so (AltTab, Rewind, ...)
// APNs has a content size limit of around 1000 characters, which is way too low for general clipboard contents

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        //for url in urls {
            //handleIncomingURL(url)
        //}
    }

    //private func handleIncomingURL(_ url: URL) {
    //    // Handle the URL here
    //    if url.scheme == "clipboardfriend" {
    //        if url.host == "test" {
    //            print("Handling clipboardfriend://test")
    //            // Insert your custom handling logic here
    //        }
    //    }
    //}
}

class AppGlobals: ObservableObject {
    @Published var pasteShortcutDisabledTemporarily: Bool = false // Disable paste to clipboard-send to be able to paste a receiver ID temporarily
}

@main
struct ClipboardFriendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var appGlobals = AppGlobals()
    @StateObject var userStore = UserStore()
    @StateObject var settingsStore = SettingsStore()
    @StateObject var clipboardManager = ClipboardManager()
    private var updateTimer: Timer?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appGlobals)
                .environmentObject(userStore)
                .environmentObject(settingsStore)
                .environmentObject(clipboardManager)
                .frame(minWidth: 400) // Min window width to now squeeze text
                .task { await userStore.load() } // Load user data
                .task { await settingsStore.load() } // Load settings
        }
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
            if !appGlobals.pasteShortcutDisabledTemporarily {
                CommandGroup(replacing: .pasteboard) {
                    Button {
                        Task {
                            await clipboardManager.sendClipboardContent()
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
