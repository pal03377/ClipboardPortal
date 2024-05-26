import SwiftUI
import UserNotifications

// TODO:
// - Setting to allow opening URLs
// - In-App-URL for Live Share (send URL directly to app)
// - Design better interface in Affinity Designer
// - Send images and files


// Reasons to fetch every Xs instead of using the Apple Notification Service APNs:
// - APNs was very hard to debug locally with a sandbox
// - The notifications were really unreliable, even with highest priority.
// - Notifications can still be prevented from being delivered because of energy consumption considerations and because of some screen recording software or so (AltTab, Rewind, ...)
// APNs has a content size limit of around 1000 characters, which is way too low for general clipboard contents

@main
struct ShareClipboardApp: App {
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
