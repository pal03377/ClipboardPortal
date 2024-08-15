import Foundation
import AppKit

import Starscream // For WebSockets

enum ClipboardManagerError {
    case encryptedMetadataEncoding
    case contentsFromStranger
}
extension ClipboardManagerError: LocalizedError { // Nice error messages
    public var errorDescription: String? {
        switch self {
        case .encryptedMetadataEncoding: "Clipboard metadata broken. Update the app."
        case .contentsFromStranger: "Received clipboard contents from a stranger. Add them as a friend first."
        }
    }
}

// Clipboard content for sending and receiving
enum ClipboardContent: Equatable, Hashable, CustomStringConvertible {
    case text(String)
    case file(URL)
    
    // String representation of content for UI. Use pattern matching for getting the text or URL.
    var description: String {
        switch self {
        case .text(let text): return text
        case .file(let url):  return url.lastPathComponent // Filename e.g. "myfile.txt"
        }
    }
    
    // Data representation for sending to the server
    var data: Data? {
        switch self {
        case .text(let text): return text.data(using: .utf8)
        case .file(let url):  return try? Data(contentsOf: url)
        }
    }
    
    // String representation of the content type for notifications
    var typeDescription: String {
        switch self {
        case .text: "text"
        case .file: "file"
        }
    }
    
    // Copy to the computer clipboard
    func copyToClipboard() {
        // Prepare clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // Clear clipboard to only have the new content in there, even if before there was e.g. an image in there as well
        // Write to clipboard
        pasteboard.clearContents() // Clear old contents
        switch self {
        case .text(let text):
            pasteboard.setString(text, forType: .string) // Copy as text
            if let _ = URL(string: text) { // Text looks like URL? -> Copy as URL
                pasteboard.setString(text, forType: .URL) // Copy as URL
            }
        case .file(let fileURL):
            pasteboard.setString(fileURL.absoluteString, forType: .fileURL) // Copy as file URL e.g. for pasting in Finder or an image into an image editing app
        }
    }
}

// Clipboard content metadata for sending
struct ClipboardContentSendMetadata: Codable {
    let senderId: String // ID of sending user e.g. "12345678"
    let encryptedContentMetadataBase64: String // Encrypted metadata including content type and filename to store as few unencrypted information as possible
    
    // Decrypted metadata object
    struct ContentMetadata: Codable {
        enum ClipboardContentType: String, Codable {
            case text = "text"
            case file = "file"
            static func fromClipboardContent(_ content: ClipboardContent) -> Self {
                switch content {
                case .text: .text
                case .file: .file
                }
            }
        }
        let type: ClipboardContentType // Type of content
        let filename: String? // Filename for files or nil
        
        static func fromEncryptedMetadataBase64(_ encryptedBase64: String, senderId: String) throws -> Self {
            guard let friend = UserStore.shared.getFriend(userId: senderId) else { throw ClipboardManagerError.contentsFromStranger }
            guard let encryptedData = Data(base64Encoded: encryptedBase64) else { throw ClipboardManagerError.encryptedMetadataEncoding }
            do {
                let metadataJson = try decrypt(encryptedData: encryptedData, friendPublicKey: friend.publicKey)
                return try JSONDecoder().decode(Self.self, from: metadataJson)
            } catch {
                print(error)
                throw ClipboardManagerError.encryptedMetadataEncoding
            }
        }
        
        func toEncryptedMetadatabase64(receiverId: String) throws -> String {
            guard let friend = UserStore.shared.getFriend(userId: receiverId) else { fatalError("Trying to encrypt metadata for a stranger. The user ID should already have been added before sending.") }
            let metadataJson = try JSONEncoder().encode(self)
            return try encrypt(data: metadataJson, friendPublicKey: friend.publicKey).base64EncodedString()
        }
    }
    /// Decrypt the metadata about the content
    func getContentMeta() throws -> ContentMetadata {
        return try .fromEncryptedMetadataBase64(self.encryptedContentMetadataBase64, senderId: self.senderId)
    }

    /// Create a metadata object with encrypted type and file metadata from a ClipboardContent object
    static func fromClipboardContent(_ content: ClipboardContent, receiverId: String) throws -> Self {
        let filename: String? = switch content { // Filename for sending
        case .file(let fileURL): fileURL.lastPathComponent // Filename e.g. "myfile.txt"
        case .text: nil
        }
        return try Self(
            senderId: UserStore.shared.user!.id,
            encryptedContentMetadataBase64: ContentMetadata(
                type: .fromClipboardContent(content),
                filename: filename
            ).toEncryptedMetadatabase64(receiverId: receiverId)
        )
    }
}
// Clipboard content metadata for receiving
struct ClipboardContentReceiveMetadata: Codable {
    let sendMetadata: ClipboardContentSendMetadata // Metadata from the sender
    let senderPublicKeyBase64: String // Base64 of the sender's public key to save one request to get it
}

// History entry to show in the UI
struct ClipboardHistoryEntry: Hashable {
    var receiveDate: Date = Date() // For unique IDs in UI list
    var content: ClipboardContent
    var received: Bool // Whether the content was sent or received
}

// Global manager to send and receive clipboard contents
class ClipboardManager: ObservableObject, WebSocketDelegate { // WebSocketDelegate to be able to receive WebSocket events from the server
    static let shared = ClipboardManager()
    
    @Published var connecting: Bool = false // Whether the app is connecting to the server
    @Published var connected: Bool  = false // Whether the manager is connected to the server
    @Published var sending: Bool    = false // Whether clipboard contents are being sent right now
    @Published var sendErrorMessage: String?    = nil // Error message when sending   the clipboard fails
    @Published var receiveErrorMessage: String? = nil // Error message when receiving the clipboard fails
    @Published var clipboardHistory: [ClipboardHistoryEntry] = [] // History of clipboard entries for the UI
    private var socket: WebSocket! // WebSocket connection to the server
    private var pingTimer: Timer? // Periodic timer to ping server to keep connection alive

    // ### Send ###
    /// Send specific clipboard content to the friend. Used with a parameter to enable re-sending clipboard contents from the history.
    struct ClipboardSendResponse: Decodable {} // Empty response from the server on send success
    func sendClipboardContent(_ content: ClipboardContent) async { // data -> to send, textForm -> to display in history
        print("Sending \(content)")
        let receiverId = SettingsStore.shared.settingsData.receiverId
        guard receiverId != "" else {
            DispatchQueue.main.async { self.sendErrorMessage = "No receiver configured. Go to settings." } // Show error if there is no receiver yet. Update UI in main thread.
            return
        }
        guard let data = content.data else {
            DispatchQueue.main.async { self.sendErrorMessage = "Could not read data from clipboard." } // Show error if reading data from clipboard failed, e.g. because of missing file. Update UI in main thread.
            return
        }
        guard let friend = try? await UserStore.shared.getOrAddFriend(userId: receiverId) else { // Automatically add people that we send our clipboard to as friends
            DispatchQueue.main.async { self.sendErrorMessage = "Could not find friend. Is the user ID in the settings correct?" } // Show error if friend does not exist, e.g. if the user ID is wrong and therefore the public key was not found
            return
        }
        guard let _ = UserStore.shared.getFriend(userId: receiverId) else { fatalError("?") }
        // Encode clipboard metadata for sending
        guard let meta = try? ClipboardContentSendMetadata.fromClipboardContent(content, receiverId: SettingsStore.shared.settingsData.receiverId),
              let metaJson = try? JSONEncoder().encode(meta) else {
            DispatchQueue.main.async { self.sendErrorMessage = "Could not encode metadata for sending." } // Show error. Update UI in main thread.
            return
        }
        // Show sending status in UI
        DispatchQueue.main.async { self.sending = true; self.sendErrorMessage = nil } // Show loading spinner in UI. Update UI in main thread.
        defer { DispatchQueue.main.async { self.sending = false } } // Hide loading spinner when done. Update UI in main thread.
        // Encrypt data
        guard let encryptedData = try? encrypt(data: data, friendPublicKey: friend.publicKey) else {
            DispatchQueue.main.async { self.sendErrorMessage = "Clipboard contents could not be encrypted." } // Show error if encrypting fails
            return
        }
        // Send data to server
        let sendUrl = serverUrl.appendingPathComponent("send").appendingPathComponent(receiverId) // Send URL for clipboard content, e.g. https://clipboardportal.pschwind.de/send/87654321
        var request = URLRequest(url: sendUrl); request.httpMethod = "POST" // Create POST request
        let boundary = UUID().uuidString; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type") // Create boundary for file upload
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"meta\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(metaJson) // Send metadata JSON string
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"content\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(encryptedData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body // Set request body to file upload
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            print("Status Code: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                DispatchQueue.main.async { self.sendErrorMessage = (ServerRequestError.fromStatusCode(httpResponse.statusCode)).localizedDescription }
            }
            let responseString = String(data: data, encoding: .utf8)!
            print("Response: \(responseString)")
            DispatchQueue.main.async {
                self.clipboardHistory.append(ClipboardHistoryEntry(content: content, received: false))
                playSoundEffect(.send)
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            DispatchQueue.main.async { self.sendErrorMessage = error.localizedDescription }
        }
    }
    /// Send the computer clipboard to the friend.
    func sendClipboardContent() async {
        if let fileUrlString = NSPasteboard.general.propertyList(forType: .fileURL) as? String { // File in clipboard?
            guard let fileUrl = URL(string: fileUrlString) else { await self.sendClipboardContent(.text(fileUrlString)); return } // Fall back to sending the file URL if it cannot be read as a URL
            await self.sendClipboardContent(.file(fileUrl)) // Send file
        } else if var content = NSPasteboard.general.string(forType: .string) { // Text in clipboard?
            if content == "rick" { content = "https://www.youtube.com/watch?v=xvFZjo5PgG0" } // Easter egg
            await self.sendClipboardContent(.text(content)) // Send text
        } else { // No supported clipboard content?
            DispatchQueue.main.async { self.sendErrorMessage = "No sendable clipboard content." } // Show error. Update UI in main thread.
        }
    }
    
    
    // ### Receive ###
    /// Start websocket connection to server to get updates for new clipboard contents
    func connectForUpdates() {
        guard let _ = UserStore.shared.user else { return } // Only start connections when a user exists because before that it won't work
        DispatchQueue.main.async { self.connecting = true; self.receiveErrorMessage = nil } // Reset last receive error message and mark as connecting
        var request = URLRequest(url: wsServerUrl)
        request.timeoutInterval = 10 * 365 * 24 * 60 * 60 // Wait as long as possible until clipboard content arrives
        socket = WebSocket(request: request)
        socket.delegate = self
        socket.connect()
    }
    private func retryConnectForUpdatesAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { // Retry connecting after Xs
            self.connectForUpdates()
        }
    }
    private struct UserInitialMessageDTO: Encodable { var id: String }
    // Receive WebSocket events
    struct WebsocketServerMessage: Codable {
        var event: String // Event type, e.g. "new" or "forbidden"
        var meta: ClipboardContentSendMetadata? // Clipboard content metadata or None
    }
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) { // Event listener callback for all WebSocket events
        DispatchQueue.main.async { self.connecting = false } // Not connecting any more when event was received. Update in UI thread.
        switch event {
        case .connected(let headers): // Connection established
            DispatchQueue.main.async { self.connected = true } // Update connection status. Update in UI thread.
            print("websocket is connected: \(headers)")
            // Send user ID to receive events for new clipboard contents
            guard let user = UserStore.shared.user else { print("Cannot connect to WebSocket without user"); return } // Require user to register for events
            do {
                try client.write(string: String(data: JSONEncoder().encode(UserInitialMessageDTO(id: user.id)), encoding: .utf8)!) // Send initial greeting message to server with user ID to get updates for that ID
                pingTimer?.invalidate() // Cancel previous ping task to restart it
                pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { timer in // Ping every Xs to keep the server connection alive
                    guard self.connected else { timer.invalidate(); return } // Stop pinging when server is disconnected
                    client.write(ping: Data()) // Ping server to keep connection alive
                }
            } catch { // Error while sending greeting message?
                DispatchQueue.main.async { self.receiveErrorMessage = "User does not exist"; self.connected = false } // Update connection status. Update in UI thread.
                self.retryConnectForUpdatesAfterDelay() // Retry later
            }
        case .disconnected(let reason, let code): // Disconnected
            print("Websocket is disconnected: \(reason) with code: \(code)")
            DispatchQueue.main.async { // Update in UI thread
                self.receiveErrorMessage = self.receiveErrorMessage ?? "Disconnected from the server" // Keep current error message or just say "Disconnected" if no detail is known
                self.connected = false
            }
            self.retryConnectForUpdatesAfterDelay() // Retry later
        case .text(let message): // Received text event from server
            print("Received message: \(message)")
            guard let messageData = message.data(using: .utf8), let serverMessage = try? JSONDecoder().decode(WebsocketServerMessage.self, from: messageData) else {
                print("Unknown text from server")
                DispatchQueue.main.async { self.receiveErrorMessage = "Server sent unknown event: \(message) Please update the app." } // Show error. Update in UI thread.
                return
            }
            switch serverMessage.event {
            case "new": // Event "New clipboard contents available"
                Task { await self.downloadAndReceiveClipboardContent(serverMessage: serverMessage) } // Download the new received clipboard content from server
                break
            case "forbidden": // Event "Authentication failed"
                DispatchQueue.main.async { self.receiveErrorMessage = "Could not authenticate with server. Use File > Reset User to fix this." } // Show message to resolve error. Update in UI thread.
                break
            default:
                print("Unknown event from server: \(serverMessage.event)")
                DispatchQueue.main.async { self.receiveErrorMessage = "Server sent unknown event: \(serverMessage.event). Please update the app." } // Show error. Update in UI thread.
            }
        case .binary:
            print("Unsupported binary data from server")
            DispatchQueue.main.async { self.receiveErrorMessage = "Server sent unsupported binary data" } // Show error. Update in UI thread.
        case .ping: break // Ignore ping events
        case .pong: break // Ignore pong events
        case .viabilityChanged(let connected): // Connection status changed?
            DispatchQueue.main.async { self.connected = connected } // Show new connection status in status view on the bottom right
            break
        case .reconnectSuggested: // Connection should be restarted?
            self.retryConnectForUpdatesAfterDelay() // Restart connection after delay
            break
        case .cancelled: // Connection cancelled
            DispatchQueue.main.async { self.connected = false } // Update connection status
            self.retryConnectForUpdatesAfterDelay() // Retry after delay
        case .error(let error): // Connection error?
            DispatchQueue.main.async { // Show connection error. Update in UI thread.
                if let error, case HTTPUpgradeError.notAnUpgrade(let code, _) = error { // Detected server error? e.g. 502
                    let serverRequestErr = ServerRequestError.fromStatusCode(code)
                    self.receiveErrorMessage = serverRequestErr.localizedDescription // Show user-friendly server error message
                } else {
                    self.receiveErrorMessage = error?.localizedDescription
                }
                self.connected = false
            }
            self.retryConnectForUpdatesAfterDelay() // Retry after delay
        case .peerClosed: // Server closed connection? e.g. server is restarting
            DispatchQueue.main.async { self.connected = false } // Update connection status
            self.retryConnectForUpdatesAfterDelay() // Retry after delay
        }
    }
    
    /// Download the current clipboard content from server (and paste to text clipboard or save in Downloads)
    func downloadAndReceiveClipboardContent(serverMessage: WebsocketServerMessage) async {
        guard let user = UserStore.shared.user else {
            DispatchQueue.main.async { self.receiveErrorMessage = "No user found when downloading clipboard content" } // Update UI in main thread
            return
        }
        guard let meta = serverMessage.meta else {
            DispatchQueue.main.async { self.receiveErrorMessage = "Server response misses metadata. Update the app." } // Update UI in main thread
            return
        }
        guard let senderId = serverMessage.meta?.senderId else {
            DispatchQueue.main.async { self.sendErrorMessage = "Could not find the person that sent the clipboard contents." } // Show error if friend does not exist
            return
        }
        guard let friend = UserStore.shared.getFriend(userId: senderId) else {
            // Show friend request from sender and continue copying the contents when accepted
            FriendRequest.shared.showRequest(userId: senderId) { Task { await self.downloadAndReceiveClipboardContent(serverMessage: serverMessage) } }
            return
        }
        DispatchQueue.main.async { FriendRequest.shared.reset() } // Reset pending friend requests when successfully receiving content. Update UI in main thread.
        DispatchQueue.main.async { self.receiveErrorMessage = nil } // Reset last receive error message
        var contentMeta: ClipboardContentSendMetadata.ContentMetadata?
        do { contentMeta = try meta.getContentMeta() }
        catch {
            DispatchQueue.main.async { self.receiveErrorMessage = error.localizedDescription } // Update UI in main thread
            return
        }
        guard let contentMeta = contentMeta else { return } // Make Swift happy my declaring contentMeta as a constant
        let contentUrl = serverUrl.appendingPathComponent(user.id) // Download URL for clipboard content, e.g. https://clipboardportal.pschwind.de/12345678
        let downloadTask = URLSession.shared.downloadTask(with: contentUrl) { (location, response, error) in // Download clipboard content
            guard let location = location, error == nil else {
                print("Download error: \(String(describing: error))")
                self.receiveErrorMessage = error?.localizedDescription
                return
            }
            do {
                let encryptedData = try Data(contentsOf: location)
                let data = try decrypt(encryptedData: encryptedData, friendPublicKey: friend.publicKey) // Decrypt encrypted clipboard contents
                // Check if the file is a text or a file
                if contentMeta.type == .text, let text = String(data: data, encoding: .utf8) { // Text clipboard contents?
                    print("Got text \(text)")
                    Task { await self.onReceivedClipboardContent(.text(text)) }
                } else if contentMeta.type == .file { // File clipboard contents?
                    print("Got file \(location)")
                    try data.write(to: location) // Write decrypted contents into file
                    do {
                        // Move the temporary file into the Downloads folder
                        let downloadFolderFileURL = try moveFileToDownloadsFolder(fileURL: location, preferredFilename: contentMeta.filename!)
                        // Copy the file to the clipboard, update the history and send a notification
                        Task { await self.onReceivedClipboardContent(.file(downloadFolderFileURL)) }
                    } catch {
                        print(error)
                        DispatchQueue.main.async { self.receiveErrorMessage = "Saving download failed: " + error.localizedDescription }
                    }
                } else {
                    print("Unexpected server message meta type")
                    DispatchQueue.main.async { self.receiveErrorMessage = "Unexpected server message meta type. Please update the app." }
                }
            } catch {
                print("File handling or decryption error: \(error)")
                DispatchQueue.main.async { self.receiveErrorMessage = error.localizedDescription }
            }
        }
        downloadTask.resume()
    }
    
    /// Handle received and downloaded clipboard content (sound effect, notification, UI updates, ...)
    private func onReceivedClipboardContent(_ content: ClipboardContent) async {
        // Play sound effect
        playSoundEffect(.receive)
        // Copy to clipboard
        content.copyToClipboard()
        // Add to history
        DispatchQueue.main.async { self.clipboardHistory.append(ClipboardHistoryEntry(content: content, received: true)) } // Update clipboard history. Update UI in main thread.
        // Show notification
        await showClipboardContentNotification(content)
        // Open URLs in browser
        if case let ClipboardContent.text(textContent) = content {
            if (textContent.starts(with: "http:") || textContent.starts(with: "https:")) && !textContent.contains(" "), let url = URL(string: textContent) { // Text content looks like URL?
                NSWorkspace.shared.open(url) // Open URL in browser
            }
        }
    }
}
