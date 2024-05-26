import Fluent

final class UserModel: Model {
    static let schema = "users" // DB table name    
    @ID(custom: "id", generatedBy: .user) var id: String? // User ID to choose who to send clipboard contents to. 8 digits. e.g. "12345678"
    @Field(key: "apns_token") var apnsToken: String // APNs token to send clipboard contents with push notifications. e.g. "1a2b3c..."
    @Field(key: "secret") var secret: String? // Secret to allow updating the APNs token and fetching the last clipboard content. Using the ID would be insecure because the ID is public. e.g. "1a2b3c..."
    @Field(key: "last_received_clipboard_content") var lastReceivedClipboardContent: ClipboardContent? // Last clipboard content received from another user. Needed because of the small payload size limit of APNs. e.g. "Hello, world!

    init() {}
    init(id: String?, apnsToken: String, secret: String? = nil, lastReceivedClipboardContent: ClipboardContent? = nil) {
        self.id = id ?? Self.generateRandomID()
        self.apnsToken = apnsToken
        self.secret = secret ?? Self.generateRandomSecret()
        self.lastReceivedClipboardContent = lastReceivedClipboardContent
    }
    convenience init(apnsToken: String) {
        self.init(id: nil, apnsToken: apnsToken)
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
            .field("apns_token", .string, .required)
            .field("secret", .string)
            .field("last_received_clipboard_content", .json)
            .create()
    }
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema(UserModel.schema).delete()
    }
}