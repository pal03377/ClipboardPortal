import Foundation
import SwiftUI

// Store the receiver of your clipboard (user ID of receiver, e.g. "12345678")
class ReceiverStore: ObservableObject {
    @Published var receiverId: String?

    // Helper function to get the file path for the user data
    private static func fileURL() throws -> URL { // e.g. ~/Library/Application Support/receiver.data
        try FileManager.default.url(for: .applicationSupportDirectory, // Store data in ~/Library/Application Support
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
            .appendingPathComponent("receiver.data")
    }

    // Load receiver ID from storage
    func load() async {
        let fileURL = try! Self.fileURL() // Get the filepath
        let data = try? Data(contentsOf: fileURL) // Read user data from file
        guard let data else { // Nothing saved yet
            DispatchQueue.main.async { self.receiverId = nil } // Update UI with no receiver ID if nothing was saved yet
            return
        }
        let decodedId = try? JSONDecoder().decode(String?.self, from: data) // Decode string from JSON
        DispatchQueue.main.async { self.receiverId = decodedId } // Update UI on main thread
    }

    // Helper function to save the receiver ID locally
    func save(receiverId: String) async throws {
        DispatchQueue.main.async { self.receiverId = receiverId } // Update UI on main thread
        let data = try JSONEncoder().encode(receiverId) // JSON-encode user data
        let outfile = try Self.fileURL() // Get filepath e.g. ~/Library/Application Support/receiver.data
        try data.write(to: outfile) // Write user data to file
    }

    // Delete the user data file to reset the user
    func delete() async throws {
        DispatchQueue.main.async { self.receiverId = nil } // Update UI on main thread
        let fileURL = try Self.fileURL() // Get filepath e.g. ~/Library/Application Support/receiver.data
        try FileManager.default.removeItem(at: fileURL) // Delete user data file
    }

    // Validate the receiver ID to be an 8-digit number
    func validate(receiverId: String) async throws {
        guard receiverId.count == 8 else { throw NSError(domain: "ReceiverStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Receiver ID must be an 8-digit number"]) }
        guard Int(receiverId) != nil else { throw NSError(domain: "ReceiverStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Receiver ID must be an 8-digit number"]) }
    }
}
