import SwiftUI

struct FriendRequestView: View {
    @ObservedObject var friendRequest = FriendRequest.shared
    
    var body: some View {
        HStack {
            if let requestingUserId = friendRequest.requestingUserId {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Friend request from \(requestingUserId)")
                        HStack {
                            if let errorMsg = friendRequest.errorMessage {
                                Text(errorMsg)
                                    .foregroundStyle(.red)
                            } else {
                                Image(systemName: "exclamationmark.triangle")
                                    .imageScale(.small)
                                Text("This will allow them to write to your clipboard. Caution!")
                                    .font(.footnote)
                            }
                        }
                    }
                    Spacer()
                    if !friendRequest.loading {
                        Button("Accept") { Task { await friendRequest.acceptCurrentFriendRequest() } }
                        Button("Deny") { friendRequest.denyCurrentFriendRequest() }
                    } else { // Loading?
                        ProgressView().scaleEffect(0.5)
                    }
                }
            }
        }
    }
}

#Preview("Friend request") {
    FriendRequestView()
        .onAppear {
            FriendRequest.shared.showRequest(userId: "12345678") {}
        }
        .padding()
        .frame(width: 400)
}
#Preview("Friend request loading") {
    FriendRequestView()
        .onAppear {
            FriendRequest.shared.showRequest(userId: "12345678") {}
            FriendRequest.shared.loading = true
        }
        .padding()
        .frame(width: 400)
}
#Preview("Friend request error") {
    FriendRequestView()
        .onAppear {
            FriendRequest.shared.showRequest(userId: "12345678") {}
            FriendRequest.shared.errorMessage = "Some error message"
        }
        .padding()
        .frame(width: 400)
}
#Preview("No friend request") {
    FriendRequestView()
        .padding()
        .frame(width: 400)
}
