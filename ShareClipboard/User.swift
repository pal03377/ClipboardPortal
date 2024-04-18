struct User: Codable {
    var id: String // User ID to choose who to send clipboard contents to. 8 digits. e.g. "12345678"
    var apnsToken: String // APNs token to send clipboard contents with push notifications. e.g. "1a2b3c..."
    var updateSecret: String // Secret to allow updating the APNs token. Using the ID would be insecure because the ID is public. e.g. "1a2b3c..."
}
