import Foundation
import Fluent

final class UserModel: Model {
    static let schema = "users" // DB table name    
    @ID(custom: "id", generatedBy: .user) var id: String? // User ID to choose who to send clipboard contents to. 8 digits. e.g. "12345678"
    @Field(key: "secret") var secret: String? // Secret to allow fetching the last clipboard content. Using the ID would be insecure because the ID is public. e.g. "1a2b3c..."
    @Field(key: "last_received_clipboard_content") var lastReceivedClipboardContent: ClipboardContent? // Last clipboard content received from another user. e.g. "Hello, World!"

    convenience init() { self.init(id: nil) }
    init(id: String?, secret: String? = nil, lastReceivedClipboardContent: ClipboardContent? = nil) {
        self.id = id ?? Self.generateRandomID()
        self.secret = secret ?? Self.generateRandomSecret()
        self.lastReceivedClipboardContent = lastReceivedClipboardContent
    }

    // Create random ID for user e.g. "12345678"
    static func generateRandomID() -> String {
        return Int.random(in: 10000000...99999999).description.padding(toLength: 8, withPad: "0", startingAt: 0) // Generate a random 8-digit ID e.g. "12345678"
    }
    // Create random secret for user e.g. "1a2b3c..."
    static func generateRandomSecret() -> String {
        return UUID().uuidString // Generate a random UUID as a secret e.g. "1a2b3c..."
    }
}

// Create the user table migration
struct CreateUser: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema(UserModel.schema)
            .field("id", .string, .identifier(auto: false)) // Allow ID to be a string -> no .id()
            .field("secret", .string)
            .field("last_received_clipboard_content", .json)
            .create()
    }
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema(UserModel.schema).delete()
    }
}