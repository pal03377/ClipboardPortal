import Foundation

enum ClipboardContentTypes: String, Codable {
    case text = "text"
}

struct ClipboardContent: Codable {
    var id: UUID? // Server sets UUID when sending
    var type: ClipboardContentTypes
    var content: String
    var isTruncated: Bool = false // Whether the content was truncated to fit into the APNs limits

    // Get truncated copy of the clipboard content
    func truncated() -> ClipboardContent {
        if content.count <= 200 { return self } // Don't truncate if already truncated or content is short enough
        var copy = self
        copy.isTruncated = true
        copy.content = String(copy.content.prefix(200)) // Truncate content to fit into APNs limits
        return copy
    }
}