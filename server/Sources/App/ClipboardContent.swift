import Foundation

enum ClipboardContentTypes: String, Codable {
    case text = "text"
}

struct ClipboardContent: Codable {
    var id: UUID? // Server sets UUID when sending
    var type: ClipboardContentTypes
    var content: String
}