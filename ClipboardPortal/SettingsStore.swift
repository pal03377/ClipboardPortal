import Foundation
import SwiftUI

// Settings model
struct SettingsData: Codable {
    var receiverId: String
    var notificationsEnabled: Bool
    var sendSoundEnabled: Bool
    var receiveSoundEnabled: Bool
    var mediaControlsEnabled: Bool
    var sentItemsCount: Int
    var receivedItemsCount: Int
    var totalTransferredBytes: Int

    enum CodingKeys: String, CodingKey {
        case receiverId
        case notificationsEnabled
        case sendSoundEnabled
        case receiveSoundEnabled
        case mediaControlsEnabled
        case sentItemsCount
        case receivedItemsCount
        case totalTransferredBytes
    }

    init(
        receiverId: String,
        notificationsEnabled: Bool,
        sendSoundEnabled: Bool,
        receiveSoundEnabled: Bool,
        mediaControlsEnabled: Bool = false,
        sentItemsCount: Int = 0,
        receivedItemsCount: Int = 0,
        totalTransferredBytes: Int = 0
    ) {
        self.receiverId = receiverId
        self.notificationsEnabled = notificationsEnabled
        self.sendSoundEnabled = sendSoundEnabled
        self.receiveSoundEnabled = receiveSoundEnabled
        self.mediaControlsEnabled = mediaControlsEnabled
        self.sentItemsCount = sentItemsCount
        self.receivedItemsCount = receivedItemsCount
        self.totalTransferredBytes = totalTransferredBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.receiverId = try container.decode(String.self, forKey: .receiverId)
        self.notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        self.sendSoundEnabled = try container.decode(Bool.self, forKey: .sendSoundEnabled)
        self.receiveSoundEnabled = try container.decode(Bool.self, forKey: .receiveSoundEnabled)
        self.mediaControlsEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaControlsEnabled) ?? false
        self.sentItemsCount = try container.decodeIfPresent(Int.self, forKey: .sentItemsCount) ?? 0
        self.receivedItemsCount = try container.decodeIfPresent(Int.self, forKey: .receivedItemsCount) ?? 0
        self.totalTransferredBytes = try container.decodeIfPresent(Int.self, forKey: .totalTransferredBytes) ?? 0
    }
}

// Store the settings locally
@MainActor
class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let defaultSettingsData = SettingsData(receiverId: "", notificationsEnabled: false, sendSoundEnabled: false, receiveSoundEnabled: false)
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
        guard let settingsData = try? JSONDecoder().decode(SettingsData.self, from: data) else { return } // Decode string from JSON
        self.settingsData = settingsData
    }

    // Helper function to save the receiver ID locally
    func save() async throws {
        let data = try JSONEncoder().encode(settingsData) // JSON-encode user data
        let outfile = try Self.fileURL() // Get filepath e.g. file:///Users/paul/Library/Containers/de.pschwind.ClipboardPortal/Data/Library/Application%20Support/settings.data
        try data.write(to: outfile) // Write user data to file
    }

    func registerSentTransfer(byteCount: Int) {
        settingsData.sentItemsCount += 1
        settingsData.totalTransferredBytes += max(0, byteCount)
        Task {
            do { try await self.save() }
            catch { print("Failed to save counters: \(error)") }
        }
    }

    func registerReceivedTransfer(byteCount: Int) {
        settingsData.receivedItemsCount += 1
        settingsData.totalTransferredBytes += max(0, byteCount)
        Task {
            do { try await self.save() }
            catch { print("Failed to save counters: \(error)") }
        }
    }
}
