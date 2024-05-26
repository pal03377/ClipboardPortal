import Foundation
import AppKit

enum ClipboardContentTypes: String, Codable {
    case text = "text"
}

struct ClipboardContent: Codable, Equatable, Hashable {
    var id: UUID? // Server sets UUID when sending
    var type: ClipboardContentTypes
    var content: String
    var isTruncated: Bool = false // Whether the content was truncated to fit into the APNs limits
}

struct ClipboardHistoryEntry: Hashable {
    var clipboardContent: ClipboardContent
    var received: Bool // Whether the content was sent or received
}

// Send and receive clipboard contents
class ClipboardManager: ObservableObject {
    @Published var sending: Bool = false // Whether clipboard contents are being sent right now
    @Published var sendErrorMessage: String? = nil // Error message when sending the clipboard fails
    @Published var receiveErrorMessage: String? = nil // Error message when receiving the clipboard fails (because of an error while un-truncating the content)
    @Published var clipboardHistory: [ClipboardHistoryEntry] = []
    var receiverId: String? = nil // Needs to be set from outside because the ShareClipboardApp does not know it, so the ContentView has to update it
    
    // Write content into the clipboard and record the history
    func receiveClipboardContent(_ content: ClipboardContent, user: User? = nil) async { // isTruncated -> Whether the clipboard content was truncated to fit into the APNs payload and has to be fetched from the server
        DispatchQueue.main.async { self.receiveErrorMessage = nil } // Reset last receive error message
        var fullContent = content
        if fullContent.isTruncated { // Clipboard content was truncated? Fetch full contents from the server
            do {
                if let user = user, let fetchedContent = try await fetchFullClipboardContents(for: user) {
                    fullContent = fetchedContent
                } else {
                    print("Warning: Could not get full content from server! Falling back to truncated content \(content). User: \(user.debugDescription)")
                }
            } catch {
                DispatchQueue.main.async { self.receiveErrorMessage = error.localizedDescription }
                return
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // Clear clipboard to only have the new content in there, even if before there was e.g. an image in there as well
        pasteboard.declareTypes([.string], owner: nil) // Prepare clipboard to receive string contents
        pasteboard.setString(fullContent.content, forType: .string) // Put string into clipboard
        let fullContentConstant = fullContent // Constant with full content to stop Swift from complaining about concurrency
        DispatchQueue.main.async { self.clipboardHistory.append(ClipboardHistoryEntry(clipboardContent: fullContentConstant, received: true)) } // Record new clipboard contents in history. Update UI in main thread.
    }
    
    // Fetch the full clipboard content from the server if it was truncated
    struct ClipboardContentReceiveDTO: Encodable {
        var id: String
        var secret: String
        var skipForId: UUID? // Skip sending for clipboard content ID to avoid too much traffic
    }
    struct ClipboardContentReceiveResponse: Decodable {
        var clipboardContent: ClipboardContent?
    }
    func fetchFullClipboardContents(for user: User, skipCurrent: Bool = false) async throws -> ClipboardContent? { // skipCurrent -> Whether to return nil for the latest clipboard content (to cause less traffic)
        let skipClipboardContentId: UUID? = if skipCurrent {
            clipboardHistory.filter({ $0.received }).last?.clipboardContent.id // Ignore last received clipboard content ID
        } else { nil }
        let clipboardContentResponse: ClipboardContentReceiveResponse = try await ServerRequest.post(path: "/receive", body: ClipboardContentReceiveDTO(id: user.id, secret: user.secret, skipForId: skipClipboardContentId))
        return clipboardContentResponse.clipboardContent
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
        guard let receiverId = self.receiverId else {
            DispatchQueue.main.async { self.sendErrorMessage = "No receiver configured." } // Show error if there is no receiver yet. Update UI in main thread.
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
            DispatchQueue.main.async { self.sendErrorMessage = error.localizedDescription } // Show error. Update UI in main thread.
        }
    }
    func sendClipboardContent() async {
        let pasteboard = NSPasteboard.general
        if let content = pasteboard.string(forType: .string) {
            await self.sendClipboardContent(content: ClipboardContent(type: .text, content: content))
        } else {
            DispatchQueue.main.async { self.sendErrorMessage = "No sendable clipboard content." } // Show error. Update UI in main thread.
        }
    }
    // Function to periodically load the current clipboard contents from the server directly because APNs is really slow sometimes. Returns whether there was new content.
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
}
