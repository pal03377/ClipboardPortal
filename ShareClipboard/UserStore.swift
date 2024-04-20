import SwiftUI

// Create user on server, update the APN token and store it locally
class UserStore: ObservableObject {
    @Published var user: User? = nil

    // Helper function to get the file path for the user data
    private static func fileURL() throws -> URL { // e.g. file:///Users/paul/Library/Containers/de.pschwind.ShareClipboard/Data/Library/Application%20Support/user.data
        try FileManager.default.url(for: .applicationSupportDirectory, // Store data in file:///Users/paul/Library/Containers/de.pschwind.ShareClipboard/Data/Library/Application%20Support
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
            .appendingPathComponent("user.data")
    }

    // Load user from storage and send APN updates to the server if the user exists - or create a new user on the server if it does not.
    func load(apnToken: String) async throws {
        let fileURL = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ShareClipboard/Data/Library/Application%20Support/user.data
        print(fileURL)
        // Ensure the file exists before trying to read it
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // If no file exists, create a new user on the server
            let newUser = try await createUserOnServer(apnToken: apnToken)
            DispatchQueue.main.async { self.user = newUser } // Update UI on main thread
            try await save(user: newUser) // Store user data locally
            return
        }
        let data = try Data(contentsOf: fileURL) // Read user data from file
        let storedUser = try JSONDecoder().decode(User?.self, from: data) // Decode user from JSON
        DispatchQueue.main.async { self.user = storedUser } // Update UI on main thread
        try await self.updateApnToken(apnToken) // Update APN token on server
    }

    // Helper function to save the user data locally
    private func save(user: User) async throws {
        let data = try JSONEncoder().encode(user) // JSON-encode user data
        let outfile = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ShareClipboard/Data/Library/Application%20Support/user.data
        try data.write(to: outfile) // Write user data to file
    }

    // Delete the user data file to reset the user
    func delete() async throws {
        DispatchQueue.main.async { self.user = nil } // Update UI on main thread
        let fileURL = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ShareClipboard/Data/Library/Application%20Support/user.data
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
        var secret: String
    }
    private func updateApnToken(_ token: String) async throws {
        guard let user, token != user.apnsToken else { return; } // No need to update if there is no user yet or the token did not change
        let _: User = try await ServerRequest.put(path: "/", body: UserUpdateDTO(id: user.id, apnsToken: user.apnsToken, secret: user.secret)) // Update user on server. Ignore response because it's just the same user again.
    }
}
