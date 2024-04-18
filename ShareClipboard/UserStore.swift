import SwiftUI

// Create user on server, update the APN token and store it locally
class UserStore: ObservableObject {
    @Published var user: User? = nil

    // Helper function to get the file path for the user data
    private static func fileURL() throws -> URL { // e.g. ~/Library/Application Support/user.data
        try FileManager.default.url(for: .applicationSupportDirectory, // Store data in ~/Library/Application Support
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
            .appendingPathComponent("user.data")
    }

    // Load user from storage and send APN updates to the server if the user exists - or create a new user on the server if it does not.
    func load(apnToken: String) async throws {
        let fileURL = try Self.fileURL() // Get filepath e.g. ~/Library/Application Support/user.data
        let data = try? Data(contentsOf: fileURL) // Read user data from file
        let storedUser = if let data { try JSONDecoder().decode(User?.self, from: data) } else { nil as User? } // Decode user from JSON
        if let user = storedUser { // User exists in local storage?
            DispatchQueue.main.async { self.user = user } // Update UI on main thread
            try await self.updateApnToken(apnToken) // Update APN token on server
        } else { // No user in local storage? Create a new user on the server.
            let newUser = try await createUserOnServer(apnToken: apnToken) // Create user on server
            DispatchQueue.main.async { self.user = newUser } // Update UI on main thread
            try await save(user: newUser) // Store user data locally
        }
    }

    // Helper function to save the user data locally
    private func save(user: User) async throws {
        let data = try JSONEncoder().encode(user) // JSON-encode user data
        let outfile = try Self.fileURL() // Get filepath e.g. ~/Library/Application Support/user.data
        try data.write(to: outfile) // Write user data to file
    }

    // Delete the user data file to reset the user
    func delete() async throws {
        DispatchQueue.main.async { self.user = nil } // Update UI on main thread
        let fileURL = try Self.fileURL() // Get filepath e.g. ~/Library/Application Support/user.data
        try FileManager.default.removeItem(at: fileURL) // Delete user data file
    }
    
    // Helper function to create a new user on the server if no user is stored
    struct UserCreateDTO: Codable {
        var apnsToken: String
    }
    private func createUserOnServer(apnToken: String) async throws -> User {
        try await ServerRequest.post(path: "/", body: UserCreateDTO(apnsToken: apnToken)) // Send create request to server and get back User
    }
    
    // Update the APN push notification token on the server if it changed
    struct UserUpdateDTO: Codable {
        var id: String
        var apnsToken: String
        var updateSecret: String
    }
    private func updateApnToken(_ token: String) async throws {
        guard let user, token != user.apnsToken else { return; } // No need to update if there is no user yet or the token did not change
        let _: User = try await ServerRequest.put(path: "/", body: UserUpdateDTO(id: user.id, apnsToken: user.apnsToken, updateSecret: user.updateSecret)) // Update user on server. Ignore response because it's just the same user again.
    }
}
