import SwiftUI

// Create user on server, update the APN token and store it locally
class UserStore: ObservableObject {
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
        DispatchQueue.main.async { self.userLoadErrorMessage = nil } // Clear previous error message
        let fileURL = try? Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/user.data
        guard let fileURL else {
            DispatchQueue.main.async { self.userLoadErrorMessage = "Could not get file URL" }
            return
        }
        print(fileURL)
        // Ensure the file exists before trying to read it
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // If no file exists, create a new user on the server
            do {
                let newUser = try await createUserOnServer()
                DispatchQueue.main.async { self.user = newUser } // Update UI on main thread
                await save(user: newUser) // Store user data locally
            } catch {
                DispatchQueue.main.async { self.userLoadErrorMessage = "User creation failed: \(error.localizedDescription)" }
            }
            return
        }
        do {
            let data = try Data(contentsOf: fileURL) // Read user data from file
            let storedUser = try JSONDecoder().decode(User?.self, from: data) // Decode user from JSON
            DispatchQueue.main.async { self.user = storedUser } // Update UI on main thread
        } catch let DecodingError.dataCorrupted(context) {
            print(context)
            DispatchQueue.main.async { self.userLoadErrorMessage = "User data corrupted" }
        } catch let DecodingError.keyNotFound(key, context) {
            print("Key '\(key)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
            DispatchQueue.main.async { self.userLoadErrorMessage = "User data key missing: \(key.stringValue)" }
        } catch let DecodingError.valueNotFound(value, context) {
            print("Value '\(value)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
            DispatchQueue.main.async { self.userLoadErrorMessage = "User data value missing: \(value)" }
        } catch let DecodingError.typeMismatch(type, context)  {
            print("Type '\(type)' mismatch:", context.debugDescription)
            print("codingPath:", context.codingPath)
            DispatchQueue.main.async { self.userLoadErrorMessage = "User data type mismatch: \(type)" }
        } catch {
            print("error: ", error)
            DispatchQueue.main.async { self.userLoadErrorMessage = "User data decoding failed: \(error.localizedDescription)" }
        }
    }

    // Helper function to save the user data locally
    private func save(user: User) async {
        do {
            let data = try JSONEncoder().encode(user) // JSON-encode user data
            let outfile = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/user.data
            try data.write(to: outfile) // Write user data to file
        } catch {
            DispatchQueue.main.async { self.userLoadErrorMessage = "User data saving failed: \(error.localizedDescription)" }
        }
    }

    // Delete the user data file to reset the user
    func delete() async {
        DispatchQueue.main.async { self.user = nil; self.userLoadErrorMessage = nil } // Update UI on main thread
        do {
            let fileURL = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/user.data
            try FileManager.default.removeItem(at: fileURL) // Delete user data file
        } catch {
            DispatchQueue.main.async { self.userLoadErrorMessage = "User data deletion failed: \(error.localizedDescription)" }
        }
    }
    
    // Update local storage for last received clipboard contents to not re-fetch when restarting the app
    func updateLastReceivedDate(_ date: Date) async {
        guard let _ = self.user else { return; }
        DispatchQueue.main.async { // Update UI in main thread
            self.user!.lastReceiveDate = date
            Task { await self.save(user: self.user!) }
        }
    }
    
    // Helper function to create a new user on the server if no user is stored
    struct UserCreateDTO: Codable {}
    private func createUserOnServer() async throws -> User {
        try await ServerRequest.post(path: "/users", body: UserCreateDTO()) // Send create request to server and get back User
    }
    
    // Update the APN push notification token on the server if it changed
    struct UserUpdateDTO: Codable {
        var id: String
        var secret: String
    }
}
