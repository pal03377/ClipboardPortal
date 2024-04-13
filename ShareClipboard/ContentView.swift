import SwiftUI
import AppKit
import GameKit

struct ContentView: View, ClipboardContentReceiver {
    @EnvironmentObject var gameCenterManager: GameCenterManager
    @State var lastSharedClipboardEntry: String = ""
    @State private var commandVListener: Any?
    
    var body: some View {
        if !gameCenterManager.isSignedIn {
            Button(action: {
                // Show Sign In sheet
                if let window = NSApplication.shared.windows.first, let rootViewController = window.contentViewController, let gkViewControllerForSignIn = gameCenterManager.gkViewControllerForSignIn {
                    rootViewController.presentAsModalWindow(gkViewControllerForSignIn)
                }
            }) {
                Text("Sign in")
            }
            .buttonStyle(.plain)
        } else if !gameCenterManager.matchedWithPlayers {
            VStack {
                Text("Signed in! 🎉")
                Button(action: {
                    do {
                        try GKLocalPlayer.local.presentFriendRequestCreator(from: NSApplication.shared.mainWindow)
                    } catch {
                        print("Error: \(error.localizedDescription).")
                    }
                }) {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                Button(action: {
                    if let window = NSApplication.shared.mainWindow, let rootViewController = window.contentViewController {
                            gameCenterManager.presentMatchmaker(from: rootViewController)
                        }
                }) {
                    Text("Start clipboard sharing")
                }
                .padding()
            }
        } else { // Matched with players?
            VStack {
                Text("Press Cmd+V to paste from clipboard")
                Text("Last shared clipboard entry: \(lastSharedClipboardEntry)")
            }
            .padding()
            .onAppear() {
                // Receive clipboard content
                self.gameCenterManager.addReceiver(self)
                // Setup Cmd+V keyboard shortcut to send clipboard content
                self.commandVListener = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (event) -> NSEvent? in
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command && event.characters == "v" {
                        // Read clipboard
                        let pasteboard = NSPasteboard.general
                        if let string = pasteboard.string(forType: .string) {
                            print("Paste string: \(string)")
                            self.lastSharedClipboardEntry = string
                            gameCenterManager.sendDataToAllPlayers(message: string)
                            return nil
                        }
                    }
                    return event
                }
            }
            .onDisappear() {
                // Clean up Command V listener
                if let commandVListener = self.commandVListener { NSEvent.removeMonitor(commandVListener) }
                self.commandVListener = nil
            }
        }
    }
    
    func receiveClipboardContent(content: String) {
        self.lastSharedClipboardEntry = content // Store received content to show it in the UI
        // Put new content in clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // Clear clipboard to avoid still having an image in it if a text is pasted
        pasteboard.setString(content, forType: .string)
    }
}

#Preview {
    ContentView()
}
