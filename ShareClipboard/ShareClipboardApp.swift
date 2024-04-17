import SwiftUI
import GameKit
import AppKit


protocol ClipboardContentReceiver {
    func receiveClipboardContent(content: String)
}

class GameCenterManager: NSObject, ObservableObject, GKMatchmakerViewControllerDelegate, GKMatchDelegate, GKLocalPlayerListener {
    @Published var isSignedIn: Bool = false
    @Published var matchedWithPlayers: Bool = false
    var gkViewControllerForSignIn: NSViewController?
    private var match: GKMatch?
    private var receivers: [ClipboardContentReceiver] = []

    override init() {
        super.init()
        authenticatePlayer()
    }
    
    func authenticatePlayer() {
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            if let gkViewController = viewController {
                // Don't present the view controller yet, just update the state
                DispatchQueue.main.async {
                    self.isSignedIn = false
                    self.gkViewControllerForSignIn = gkViewController // Store view controller to show when Sign In button is clicked
                }
            } else if GKLocalPlayer.local.isAuthenticated {
                DispatchQueue.main.async {
                    self.isSignedIn = true
                }
                print("Player is authenticated")
                GKLocalPlayer.local.register(self)
            } else {
                DispatchQueue.main.async {
                    self.isSignedIn = false
                }
                print("User authentication failed: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    func presentMatchmaker(from rootViewController: NSViewController) {
        let request = GKMatchRequest()
        request.minPlayers = 2 // The minimum number of players in the match
        request.maxPlayers = 2 // The maximum number of players in the match
        request.inviteMessage = "Let's share clipboards with each other!" // Optional custom invitation message
        if let matchmakerVC = GKMatchmakerViewController(matchRequest: request) {
            matchmakerVC.matchmakerDelegate = self
            rootViewController.presentAsModalWindow(matchmakerVC)
        }
    }
    
    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        // Handle cancellation here
        print("Matchmaking was cancelled by the user.")
        viewController.dismiss(nil)
        self.matchedWithPlayers = false
    }
    
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        // Handle errors here
        print("Matchmaking failed with error: \(error.localizedDescription)")
        viewController.dismiss(nil)
        self.matchedWithPlayers = false
    }
    
    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        // A match has been found and you can start the game
        print("A match was found.")
        viewController.dismiss(nil)
        self.matchedWithPlayers = true
        match.delegate = self // Receive events myself
        self.match = match
    }
    
    // Register to receive messages
    func addReceiver(_ receiver: ClipboardContentReceiver) {
        self.receivers.append(receiver)
    }
    
    // Receive message
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        if let message = String(data: data, encoding: .utf8) {
            // Handle the received message string here
            print("Received message: \(message) from player: \(player.alias)")
            for receiver in self.receivers {
                receiver.receiveClipboardContent(content: message)
            }
        } else {
            print("Failed to decode the received data")
        }
    }
    
    // Send message
    func sendDataToAllPlayers(message: String) {
        guard let messageData = message.data(using: .utf8) else {
            print("Failed to encode the message into data")
            return
        }
        guard let match = self.match else {
            print("No match exists yet")
            return
        }
        
        do {
            try match.sendData(toAllPlayers: messageData, with: .reliable)
        } catch {
            print("Failed to send data: \(error.localizedDescription)")
        }
    }
    
    // Handle incoming invitations
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        print("Received invite!")
        // Handle the accepted invite, by showing a matchmaker view controller
        DispatchQueue.main.async {
            if let matchmakerVC = GKMatchmakerViewController(invite: invite) {
                matchmakerVC.matchmakerDelegate = self
                // Present this from your main view controller
                if let window = NSApplication.shared.mainWindow, let rootViewController = window.contentViewController {
                    rootViewController.presentAsModalWindow(matchmakerVC)
                }
            }
        }
    }
}


@main
struct ShareClipboardApp: App {    
    @StateObject private var gameCenterManager = GameCenterManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameCenterManager)
        }
    }
}
