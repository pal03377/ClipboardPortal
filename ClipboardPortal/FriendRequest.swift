import SwiftUI

@MainActor
class FriendRequest: ObservableObject {
    static let shared = FriendRequest()
    
    @Published var requestingUserId: String? = nil // User ID that requests to be a friend, e.g. "12345678"
    @Published var loading = false
    @Published var errorMessage: String? = nil
    private var callbackAfterAccepted: (() -> ())?
    
    // Reset everything
    public func reset() {
        self.requestingUserId = nil
        self.callbackAfterAccepted = nil
        self.errorMessage = nil
        self.loading = false
    }
    
    /// Show a friend request with a callback when accepted
    func showRequest(userId: String, whenAccepted: @escaping () -> ()) {
        self.reset()
        self.requestingUserId = userId
        self.callbackAfterAccepted = whenAccepted
    }
    
    /// Accept the current friend request
    func acceptCurrentFriendRequest() async {
        self.loading = true
        defer { self.loading = false }
        do {
            let _ = try await UserStore.shared.addFriend(userId: self.requestingUserId!) // Add friend
        } catch {
            print(error)
            self.errorMessage = error.localizedDescription
            return
        }
        self.callbackAfterAccepted?()
        self.reset()
    }

    /// Deny the current friend request
    func denyCurrentFriendRequest() {
        self.reset()
    }
}
