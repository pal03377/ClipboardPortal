import Foundation
import AppKit

import Starscream // For WebSockets


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
        case .text(let text): return (textPrefix + text).data(using: .utf8) // Encode with text prefix for detection, e.g. "text: This is the content"
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
    var socket: WebSocket! // WebSocket connection to the server

    // ### Send ###
    /// Send specific clipboard content to the friend. Used with a parameter to enable re-sending clipboard contents from the history.
    struct ClipboardSendRequest: Encodable { var receiverId: String } // POST body for send request. Content is sent as file next to this request data.
    struct ClipboardSendResponse: Decodable {} // Empty response from the server on send success
    func sendClipboardContent(_ content: ClipboardContent) async { // data -> to send, textForm -> to display in history
        print("Sending \(content)")
        guard SettingsStore.shared.settingsData.receiverId != "" else {
            DispatchQueue.main.async { self.sendErrorMessage = "No receiver configured. Go to settings." } // Show error if there is no receiver yet. Update UI in main thread.
            return
        }
        guard let data = content.data else {
            DispatchQueue.main.async { self.sendErrorMessage = "Could not read data from clipboard." } // Show error if reading data from clipboard failed, e.g. because of missing file. Update UI in main thread.
            return
        }
        DispatchQueue.main.async { self.sending = true; self.sendErrorMessage = nil } // Show loading spinner in UI. Update UI in main thread.
        defer { DispatchQueue.main.async { self.sending = false } } // Hide loading spinner when done. Update UI in main thread.
        let sendUrl = serverUrl.appendingPathComponent("send") // Send URL for clipboard content, e.g. https://clipboardportal.pschwind.de/send
        let filename = switch content { // Filename for sending
        case .file(let fileURL): fileURL.lastPathComponent // Filename e.g. "myfile.txt"
        case .text(_): "text.txt" // Default filename because it does not matter
        }
        // Send data to server
        var request = URLRequest(url: sendUrl); request.httpMethod = "POST" // Create POST request
        let boundary = UUID().uuidString; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type") // Create boundary for file upload
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"receiverId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(SettingsStore.shared.settingsData.receiverId)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body // Set request body to file upload
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            print("Status Code: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                DispatchQueue.main.async { self.sendErrorMessage = (ServerRequestError(rawValue: httpResponse.statusCode) ?? .unknown).localizedDescription }
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
    func checkForUpdates() {
        guard let _ = UserStore.shared.user else { return } // Only start connections when a user exists because before that it won't work
        DispatchQueue.main.async { self.connecting = true; self.receiveErrorMessage = nil } // Reset last receive error message and mark as connecting
        var request = URLRequest(url: wsServerUrl)
        request.timeoutInterval = 10 * 365 * 24 * 60 * 60 // Wait as long as possible until clipboard content arrives
        socket = WebSocket(request: request)
        socket.delegate = self
        socket.connect()
    }
    private func retryCheckForUpdateAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { // Retry connecting after Xs
            self.checkForUpdates()
        }
    }
    private struct UserAuthenticateDTO: Encodable { // Authentication structure to auth against websocket endpoint
        var id: String
        var secret: String
        var date: String
    }
    // Event listener callback for all WebSocket events
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        DispatchQueue.main.async { self.connecting = false } // Not connecting any more when event was received. Update in UI thread.
        switch event {
        case .connected(let headers): // Connection established
            DispatchQueue.main.async { self.connected = true } // Update connection status. Update in UI thread.
            print("websocket is connected: \(headers)")
            // Send authentication to receive events for new clipboard contents
            guard let user = UserStore.shared.user else { print("Cannot connect to WebSocket without user"); return } // Require user to authenticate
            do {
                try client.write(string: String(data: JSONEncoder().encode(UserAuthenticateDTO(id: user.id, secret: user.secret, date: (user.lastReceiveDate ?? Date.distantPast).ISO8601Format())), encoding: .utf8)!) // Send initial authentication message to server
            } catch { // Error while sending authentication message?
                DispatchQueue.main.async { self.receiveErrorMessage = "Could not authenticate"; self.connected = false } // Update connection status. Update in UI thread.
                self.retryCheckForUpdateAfterDelay() // Retry later
            }
        case .disconnected(let reason, let code): // Disconnected
            print("Websocket is disconnected: \(reason) with code: \(code)")
            DispatchQueue.main.async { // Update in UI thread
                self.receiveErrorMessage = self.receiveErrorMessage ?? "Disconnected from the server" // Keep current error message or just say "Disconnected" if no detail is known
                self.connected = false
            }
            self.retryCheckForUpdateAfterDelay() // Retry later
        case .text(let message): // Received text event from server
            print("Received message: \(message)")
            if message == "new" { // Event "New clipboard contents available"
                Task { await self.downloadAndReceiveClipboardContent() } // Download the new received clipboard content from server
            } else if message == "forbidden" { // Event "Authentication failed"
                DispatchQueue.main.async { self.receiveErrorMessage = "Could not authenticate with server. Use File > Reset User to fix this." } // Show message to resolve error. Update in UI thread.
            } else { // Unknown server event
                print("Unknown text from server")
                DispatchQueue.main.async { self.receiveErrorMessage = "Server sent unknown event: \(message)" } // Show error. Update in UI thread.
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
            self.retryCheckForUpdateAfterDelay() // Restart connection after delay
            break
        case .cancelled: // Connection cancelled
            DispatchQueue.main.async { self.connected = false } // Update connection status
            self.retryCheckForUpdateAfterDelay() // Retry after delay
        case .error(let error): // Connection error?
            DispatchQueue.main.async { // Show connection error. Update in UI thread.
                if let error, case HTTPUpgradeError.notAnUpgrade(let code, _) = error, let serverRequestErr = ServerRequestError(rawValue: code) { // Detected server error? e.g. 502
                    self.receiveErrorMessage = serverRequestErr.localizedDescription // Show user-friendly server error message
                } else {
                    self.receiveErrorMessage = error?.localizedDescription
                }
                self.connected = false
            }
            self.retryCheckForUpdateAfterDelay() // Retry after delay
        case .peerClosed: // Server closed connection? e.g. server is restarting
            DispatchQueue.main.async { self.connected = false } // Update connection status
            self.retryCheckForUpdateAfterDelay() // Retry after delay
        }
    }
    
    /// Download the current clipboard content from server (and paste to text clipboard or save in Downloads)
    func downloadAndReceiveClipboardContent() async {
        guard let user = UserStore.shared.user else { fatalError("Missing user on ClipboardManager") }
        DispatchQueue.main.async { self.receiveErrorMessage = nil } // Reset last receive error message
        let contentUrl = serverUrl.appendingPathComponent("\(user.id)_\(user.secret)") // Download URL for clipboard content, e.g. https://clipboardportal.pschwind.de/12345678_ab8902d2-75c1-4dec-baae-1f5ee859e0c7
        let downloadTask = URLSession.shared.downloadTask(with: contentUrl) { (location, response, error) in // Download clipboard content
            guard let location = location, error == nil else {
                print("Download error: \(String(describing: error))")
                self.receiveErrorMessage = error?.localizedDescription
                return
            }
            do {
                let data = try Data(contentsOf: location)
                // Check if the file is a text or a file
                if let content = String(data: data, encoding: .utf8), content.hasPrefix(textPrefix) { // Text clipboard contents?
                    print("Got text \(content)")
                    Task { await self.onReceivedClipboardContent(.text(String(content.trimmingPrefix(textPrefix)))) }
                } else { // File clipboard contents?
                    print("Received file. Downloading...")
                    // Move file to another temp file because otherwise the temp file might be deleted too quickly
                    let tempLocation = try self.moveToDownloadsFolder(fileURL: location, preferredFilename: "clipboard-portal.temp")
                    // Get real filename from server and rename file
                    Task {
                        let filenameUrl = contentUrl.appendingPathExtension("filename") // Download URL for filename, e.g. https://clipboardportal.pschwind.de/12345678_ab8902d2-75c1-4dec-baae-1f5ee859e0c7.filename
                        do {
                            let filename: String = try! await ServerRequest.get(url: filenameUrl) // Download filename from server e.g. "myfile.txt"
                            let downloadFolderFileURL = try self.moveToDownloadsFolder(fileURL: tempLocation, preferredFilename: filename)
                            print("Downloaded file.")
                            // Copy the file to the clipboard, update the history and send a notification
                            await self.onReceivedClipboardContent(.file(downloadFolderFileURL))
                        } catch {
                            print(error)
                            DispatchQueue.main.async { self.receiveErrorMessage = "Saving download failed: " + error.localizedDescription }
                        }
                    }
                }
            } catch {
                print("File handling error: \(error)")
                Task { self.receiveErrorMessage = error.localizedDescription }
            }
        }
        downloadTask.resume()
    }
    // Helper function to move a file to the user's Downloads directory without overwriting a file. Returns URL to new path.
    // Might change the filename to make it unique.
    private func moveToDownloadsFolder(fileURL: URL, preferredFilename: String) throws -> URL {
        // Choose destination that does not exist
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationURL = downloadsDirectory.appendingPathComponent(preferredFilename)
        var counter = 1
        var uniqueDestinationURL = destinationURL // URL to unique destination path e.g. "myfile-2.txt" or "myfile-3.txt"
        while FileManager.default.fileExists(atPath: uniqueDestinationURL.path) { // Make filename unique e.g. "myfile.txt" -> "myfile-2.txt" or "myfile-3.txt"
            counter += 1
            uniqueDestinationURL = destinationURL.deletingLastPathComponent().appendingPathComponent("\(destinationURL.deletingPathExtension().lastPathComponent)-\(counter).\(destinationURL.pathExtension)")
        }
        // Save the file to the Downloads folder
        do {
            try FileManager.default.moveItem(at: fileURL, to: uniqueDestinationURL)
        } catch { return fileURL } // Keep original (maybe temp) file URL when file moving fails
        return uniqueDestinationURL
    }
    
    /// Handle received and downloaded clipboard content (sound effect, notification, UI updates, ...)
    private func onReceivedClipboardContent(_ content: ClipboardContent) async {
        // Play sound effect
        playSoundEffect(.receive)
        // Copy to clipboard
        content.copyToClipboard()
        // Add to history
        DispatchQueue.main.async { self.clipboardHistory.append(ClipboardHistoryEntry(content: content, received: true)) } // Update clipboard history. Update UI in main thread.
        Task { await UserStore.shared.updateLastReceivedDate(Date()) } // Update last received date to avoid getting the same clipboard content twice
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
