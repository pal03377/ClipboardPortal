enum ClipboardContentTypes: String, Codable {
    case text = "text"
    case url = "url"
    case file = "file"
}

struct ClipboardContent: Codable, Equatable, Hashable {
    var id: UUID? // Server sets UUID when sending
    var type: ClipboardContentTypes
    var content: String // Text content or URL or "file"

    // Copy to the computer clipboard
    func copyToClipboard() {
        // Prepare clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // Clear clipboard to only have the new content in there, even if before there was e.g. an image in there as well
        // Write to clipboard
        switch self.type {
        case .text:
            pasteboard.declareTypes([.string], owner: nil) // Prepare clipboard to receive string contents
            pasteboard.setString(self.content, forType: .string) // Put string into clipboard
        case .url:
            pasteboard.declareTypes([.URL, .string], owner: nil) // Prepare clipboard to receive string contents
            pasteboard.setString(self.content, forType: .URL) // Put content as URL into clipboard
            pasteboard.setString(self.content, forType: .string) // Put content as string into clipboard
        case .file:
            fatalError("TODO")
        }
    }
}



// TODO: Implement on Receiver side
if (content.starts(with: "http:") || content.starts(with: "https:")) && !content.contains(" "), let _ = URL(string: content) { // Content looks like URL?
    await self.sendClipboardContent(content: ClipboardContent(type: .url, content: content)) // Send as URL
} else { // Content is normal string?
    await self.sendClipboardContent(content: ClipboardContent(type: .text, content: content))
}