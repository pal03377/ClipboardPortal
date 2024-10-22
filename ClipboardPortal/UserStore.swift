import Foundation
import SwiftUI

// User model
struct User: Codable {
    var id: String // User ID to choose who to send clipboard contents to. 8 digits. e.g. "12345678"
    var friends: [Friend] = [] // Friends that are allowed to send the user clipboard their clipboard
}

// Friend model
struct Friend {
    var id: String // User ID for clipboard contents to. 8 digits. e.g. "12345678"
    var publicKey: PublicKey // Public key of the friend for encryption
}
// Codable friend for saving friends
extension Friend: Codable {
    // Make friend decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let rawRepresentation = try container.decode(Data.self, forKey: .publicKey)
        publicKey = try PublicKey(rawRepresentation: rawRepresentation)
    }
    // Make friend encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(publicKey.rawRepresentation, forKey: .publicKey)
    }
    // Keys for codable
    enum CodingKeys: String, CodingKey {
        case id
        case publicKey
    }
}

// Store own user
@MainActor
class UserStore: ObservableObject {
    static let shared = UserStore()
    
    @Published var user: User? = nil
    @Published var userLoadErrorMessage: String? = nil

    // Helper function to get the file path for the user data
    private static func fileURL() throws -> URL { // e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/user.data
        try FileManager.default.url(for: .applicationSupportDirectory, // Store data in file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
        .appendingPathComponent("user.data")
    }

    // Load user from storage - or create a new user on the server if it does not exist yet.
    func load() async {
        self.userLoadErrorMessage = nil // Clear previous error message
        let fileURL = try? Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/user.data
        guard let fileURL else {
            self.userLoadErrorMessage = "Could not get file URL"
            return
        }
        print(fileURL)
        // Ensure the file exists before trying to read it
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // If no file exists, create a new user on the server
            do {
                print("No user file exists, creating new user...")
                let newUser = try await createUserOnServer()
                self.user = newUser
                await save(user: newUser) // Store user data locally
            } catch {
                self.userLoadErrorMessage = "User creation failed: \(error.localizedDescription)"
            }
            return
        }
        do {
            let data = try Data(contentsOf: fileURL) // Read user data from file
            let storedUser = try JSONDecoder().decode(User?.self, from: data) // Decode user from JSON
            self.user = storedUser
        } catch let DecodingError.dataCorrupted(context) {
            print(context)
            self.userLoadErrorMessage = "User data corrupted"
        } catch let DecodingError.keyNotFound(key, context) {
            print("Key '\(key)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
            self.userLoadErrorMessage = "User data key missing: \(key.stringValue)"
        } catch let DecodingError.valueNotFound(value, context) {
            print("Value '\(value)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
            self.userLoadErrorMessage = "User data value missing: \(value)"
        } catch let DecodingError.typeMismatch(type, context)  {
            print("Type '\(type)' mismatch:", context.debugDescription)
            print("codingPath:", context.codingPath)
            self.userLoadErrorMessage = "User data type mismatch: \(type)"
        } catch {
            print("error: ", error)
            self.userLoadErrorMessage = "User data decoding failed: \(error.localizedDescription)"
        }
    }

    // Helper function to save the user data locally
    private func save(user: User) async {
        do {
            let data = try JSONEncoder().encode(user) // JSON-encode user data
            let outfile = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/user.data
            try data.write(to: outfile) // Write user data to file
        } catch {
            self.userLoadErrorMessage = "User data saving failed: \(error.localizedDescription)"
        }
    }

    // Delete the user data file to reset the user
    func delete() async {
        self.user = nil; self.userLoadErrorMessage = nil
        do {
            let fileURL = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/user.data
            try FileManager.default.removeItem(at: fileURL) // Delete user data file
        } catch {
            self.userLoadErrorMessage = "User data deletion failed: \(error.localizedDescription)"
        }
    }
    
    // Add a friend by their user ID. Fetches the friend's public key if it is not stored locally yet.
    func addFriend(userId: String) async throws -> Friend { // userID e.g. "12345678"
        // Fetch friend's public key for storage
        let friendPublicKeyBase64: String = try await ServerRequest.get(url: serverUrl.appendingPathComponent(userId).appendingPathExtension("publickey")) // Fetch friend's public key base64 from the server, e.g. https://clipboardportal.pschwind.de/12345678.pub
        let friend = try Friend(id: userId, publicKey: .fromBase64(friendPublicKeyBase64))
        await withCheckedContinuation { continuation in // Ensure that the friends array is updated before returning to avoid lots of issues with infinite loops and assumptions about the friend existing
            self.user!.friends.append(friend)
            Task { continuation.resume() }
        }
        await self.save(user: self.user!)
        return friend
    }
    
    // Get a friend or nil if the user is no friend
    func getFriend(userId: String) -> Friend? {
        return self.user?.friends.first(where: { $0.id == userId })
    }
    
    // Get friend or add them if missing
    func getOrAddFriend(userId: String) async throws -> Friend { // userID e.g. "12345678"
        if let friend = self.getFriend(userId: userId) { return friend }
        return try await self.addFriend(userId: userId)
    }
    
    // Helper function to create a new user on the server if no user is stored
    struct UserCreateRequest: Codable {
        var publicKeyBase64: String
    }
    struct UserCreateResponse: Codable {
        var id: String
    }
    private func createUserOnServer() async throws -> User {
        let userCreateRequest = UserCreateRequest(
            publicKeyBase64: try getPublicKey().rawRepresentation.base64EncodedString()
        )
        let resp: UserCreateResponse = try await ServerRequest.post(url: serverUrl.appendingPathComponent("/users"), body: userCreateRequest) // Send create request to server and get back User
        return User(id: resp.id)
    }
}
