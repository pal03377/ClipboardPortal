struct User: Codable, Equatable {
    var id: String // User ID to choose who to send clipboard contents to. 8 digits. e.g. "12345678"
    var secret: String // Secret to allow fetching the last clipboard content. Using the ID would be insecure because the ID is public. e.g. "1a2b3c..."
    var lastReceivedClipboardContent: ClipboardContent? // Last clipboard content received from another user.
}
