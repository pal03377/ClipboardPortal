import SwiftUI
import UserNotifications

// TODO:
// - Design better interface in Affinity Designer
// - Send images and files
// - In-App-URL for Live Share (send URL directly to app)


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

@main
struct ClipboardFriendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var pasteShortcutDisabledTemporarily: Bool = false // Disable paste to clipboard-send to be able to paste a receiver ID temporarily
    @StateObject var userStore = UserStore()
    @StateObject var clipboardManager = ClipboardManager()
    private var updateTimer: Timer?
    
    var body: some Scene {
        WindowGroup {
            ContentView(pasteShortcutDisabledTemporarily: $pasteShortcutDisabledTemporarily)
                .environmentObject(userStore)
                .environmentObject(clipboardManager)
                .frame(minWidth: 400) // Min window width to now squeeze text
        }
        .commands {
            SidebarCommands()
            if !pasteShortcutDisabledTemporarily {
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
                    }
                } label: { Text("Reset user") }
            }
        }
    }
}
