import Foundation
import AppKit

typealias ClipboardContent = String // Enable changing types of clipboard content later e.g. to include images

// Send and receive clipboard contents
class ClipboardManager: ObservableObject {
    @Published var sending: Bool = false // Whether clipboard contents are being sent right now
    @Published var sendErrorMessage: String? = nil // Error message when sending the clipboard fails
    @Published var clipboardHistory: [ClipboardContent] = []
    var receiverId: String? = nil // Needs to be set from outside because the ShareClipboardApp does not know it, so the ContentView has to update it
    
    // Write content into the clipboard and record the history
    func receiveClipboardContent(_ content: ClipboardContent) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // Clear clipboard to only have the new content in there, even if before there was e.g. an image in there as well
        pasteboard.declareTypes([.string], owner: nil) // Prepare clipboard to receive string contents
        pasteboard.setString(content, forType: .string) // Put string into clipboard
        DispatchQueue.main.async { self.clipboardHistory.append(content) } // Record new clipboard contents in history. Update UI in main thread.
    }

    // Send clipboard content to another user. Throws if there is no sendable clipboard content.
    struct ClipboardContentSendDTO: Codable {
        var receiverId: String // User ID for notification
        var clipboardContent: String // Clipboard contents to send
    }
    func sendClipboardContent(content: String) async {
        guard let receiverId = self.receiverId else {
            DispatchQueue.main.async { self.sendErrorMessage = "No receiver configured." } // Show error if there is no receiver yet. Update UI in main thread.
            return
        }
        DispatchQueue.main.async { self.sending = true } // Show loading spinner in UI. Update UI in main thread.
        defer { DispatchQueue.main.async { self.sending = false } } // Hide loading spinner when done. Update UI in main thread.
        do {
            let _: String = try await ServerRequest.post(path: "/send", body: ClipboardContentSendDTO(receiverId: receiverId, clipboardContent: content)) // Send clipboard content to server to trigger notification to receipient
            DispatchQueue.main.async { self.clipboardHistory.append(content) } // Record send in history. Update UI in main thread.
        } catch {
            DispatchQueue.main.async { self.sendErrorMessage = error.localizedDescription } // Show error. Update UI in main thread.
        }
    }
    func sendClipboardContent() async {
        let pasteboard = NSPasteboard.general
        if let content = pasteboard.string(forType: .string) {
            await self.sendClipboardContent(content: content)
        } else {
            DispatchQueue.main.async { self.sendErrorMessage = "No sendable clipboard content." } // Show error. Update UI in main thread.
        }
    }
}
