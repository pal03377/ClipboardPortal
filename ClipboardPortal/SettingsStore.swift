import Foundation
import SwiftUI

struct SettingsData: Codable {
    var receiverId: String
    var notificationsEnabled: Bool
}

// Store the settings locally
class SettingsStore: ObservableObject {
    static let defaultSettingsData = SettingsData(receiverId: "", notificationsEnabled: false)
    @Published var settingsData = defaultSettingsData

    // Helper function to get the file path for the user data
    private static func fileURL() throws -> URL { // e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/settings.data
        try FileManager.default.url(for: .applicationSupportDirectory, // Store data in file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
            .appendingPathComponent("settings.data")
    }

    // Load settings from storage
    func load() async {
        let fileURL = try! Self.fileURL() // Get the filepath
        let data = try? Data(contentsOf: fileURL) // Read user data from file
        guard let data else { return } // No load possible because nothing saved yet
        let settingsData = try? JSONDecoder().decode(SettingsData?.self, from: data) // Decode string from JSON
        DispatchQueue.main.async { self.settingsData = settingsData! } // Update UI on main thread
    }

    // Helper function to save the receiver ID locally
    func save() async throws {
        let data = try JSONEncoder().encode(settingsData) // JSON-encode user data
        let outfile = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/settings.data
        try data.write(to: outfile) // Write user data to file
    }
}