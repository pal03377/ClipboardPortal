import Foundation
import AppKit

enum ClipboardContentTypes: String, Codable {
    case text = "text"
    case url = "url"
}

struct ClipboardContent: Codable, Equatable, Hashable {
    var id: UUID? // Server sets UUID when sending
    var type: ClipboardContentTypes
    var content: String

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
        }
    }
}

struct ClipboardHistoryEntry: Hashable {
    var clipboardContent: ClipboardContent
    var received: Bool // Whether the content was sent or received
}

// Send and receive clipboard contents
class ClipboardManager: ObservableObject, Equatable {
    @Published var sending: Bool = false // Whether clipboard contents are being sent right now
    @Published var sendErrorMessage: String? = nil // Error message when sending the clipboard fails
    @Published var receiveErrorMessage: String? = nil // Error message when receiving the clipboard fails
    @Published var clipboardHistory: [ClipboardHistoryEntry] = []
    var receiverId: String? = nil // Needs to be set from outside because the ClipboardPortalApp does not know it, so the ContentView has to update it
    
    var lastReceivedContent: ClipboardContent? {
        get { clipboardHistory.filter(\.received).last?.clipboardContent }
    }

    // Write content into the clipboard and record the history
    func receiveClipboardContent(_ content: ClipboardContent, user: User? = nil) async {
        DispatchQueue.main.async { self.receiveErrorMessage = nil } // Reset last receive error message
        content.copyToClipboard() // Copy to computer clipboard
        if content.type == .url, let url = URL(string: content.content) { NSWorkspace.shared.open(url) } // Open received URL in browser
        DispatchQueue.main.async { self.clipboardHistory.append(ClipboardHistoryEntry(clipboardContent: content, received: true)) } // Update clipboard history. Update UI in main thread.
    }

    // Fetch the clipboard content from the server
    struct ClipboardContentReceiveDTO: Encodable {
        var id: String
        var secret: String
        var skipForId: UUID? // Skip sending for clipboard content ID to avoid too much traffic
    }
    struct ClipboardContentReceiveResponse: Decodable {
        var clipboardContent: ClipboardContent?
    }
    func fetchFullClipboardContents(for user: User, skipCurrent: Bool = false) async throws -> ClipboardContent? { // skipCurrent -> Whether to return nil for the latest clipboard content (to cause less traffic)
        let clipboardContentResponse: ClipboardContentReceiveResponse = try await ServerRequest.post(path: "/receive", body: ClipboardContentReceiveDTO(id: user.id, secret: user.secret, skipForId: skipCurrent ? user.lastReceivedClipboardContent?.id : nil))
        return clipboardContentResponse.clipboardContent
    }
    // Periodically load the current clipboard contents from the server. Returns whether there was new content.
    func checkForUpdates(user: User) async -> Bool {
        do {
            DispatchQueue.main.async { self.receiveErrorMessage = nil } // Reset last receive error message
            if let newClipboardContents = try await fetchFullClipboardContents(for: user, skipCurrent: true) { // New clipboard contents found on the server?
                print("Found new clipboard contents! \(newClipboardContents)")
                await receiveClipboardContent(newClipboardContents, user: user) // Handle new clipboard contents
                return true
            }
        } catch {
            DispatchQueue.main.async { self.receiveErrorMessage = error.localizedDescription } // Update UI on main thread
        }
        return false
    }

    // Send clipboard content to another user. Throws if there is no sendable clipboard content.
    struct ClipboardContentSendDTO: Encodable {
        var receiverId: String // User ID for notification
        var clipboardContent: ClipboardContent // Clipboard contents to send
    }
    struct ClipboardSendResponse: Decodable {
        var id: UUID // ID of the clipboard content
    }
    func sendClipboardContent(content: ClipboardContent) async {
        print("sending \(content)")
        guard let receiverId = self.receiverId, receiverId != "" else {
            DispatchQueue.main.async { self.sendErrorMessage = "No receiver configured. Go to settings." } // Show error if there is no receiver yet. Update UI in main thread.
            return
        }
        DispatchQueue.main.async { self.sending = true; self.sendErrorMessage = nil } // Show loading spinner in UI. Update UI in main thread.
        defer { DispatchQueue.main.async { self.sending = false } } // Hide loading spinner when done. Update UI in main thread.
        do {
            let clipboardSendResp: ClipboardSendResponse = try await ServerRequest.post(path: "/send", body: ClipboardContentSendDTO(receiverId: receiverId, clipboardContent: content)) // Send clipboard content to server to trigger notification to receipient
            DispatchQueue.main.async {
                // Record send in history. Update UI in main thread.
                var contentWithId = content
                contentWithId.id = clipboardSendResp.id // Update ID from server
                self.clipboardHistory.append(ClipboardHistoryEntry(clipboardContent: contentWithId, received: false))
            }
        } catch {
            // Make known errors look better
            let errorMessage = if let error = error as? ServerRequestError {
                switch error {
                case .notFound: "This receiver ID does not exist."
                default: error.localizedDescription
                }
            } else { error.localizedDescription }
            // Show error
            DispatchQueue.main.async { self.sendErrorMessage = errorMessage } // Show generic error. Update UI in main thread.
        }
    }
    func sendClipboardContent() async {
        let pasteboard = NSPasteboard.general
        if var content = pasteboard.string(forType: .string) {
            if content == "rick" { content = "https://www.youtube.com/watch?v=xvFZjo5PgG0" } // Easter egg
            if (content.starts(with: "http:") || content.starts(with: "https:")) && !content.contains(" "), let _ = URL(string: content) { // Content looks like URL?
                await self.sendClipboardContent(content: ClipboardContent(type: .url, content: content)) // Send as URL
            } else { // Content is normal string?
                await self.sendClipboardContent(content: ClipboardContent(type: .text, content: content))
            }
        } else {
            DispatchQueue.main.async { self.sendErrorMessage = "No sendable clipboard content." } // Show error. Update UI in main thread.
        }
    }
    
    static func == (lhs: ClipboardManager, rhs: ClipboardManager) -> Bool {
        return lhs.sending == rhs.sending && lhs.clipboardHistory == rhs.clipboardHistory && lhs.receiverId == rhs.receiverId
    }
}
