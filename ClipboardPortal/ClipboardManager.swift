import Foundation
import AppKit

import Starscream // For WebSockets


enum ClipboardContent: Equatable, Hashable, CustomStringConvertible {
    case text(String)
    case file(URL)
    
    var description: String {
        switch self {
        case .text(let text): return text
        case .file(let url):  return url.absoluteString
        }
    }
    
    var data: Data? { // Data for sending
        print("Read data of \(self)")
        switch self {
        case .text(let text): return (textPrefix + text).data(using: .utf8) // Encode with text prefix for detection, e.g. "text: This is the content"
        case .file(let url):  return try? Data(contentsOf: url)
        }
    }
    
    // Copy to the computer clipboard
    func copyToClipboard() {
        // Prepare clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // Clear clipboard to only have the new content in there, even if before there was e.g. an image in there as well
        // Write to clipboard
        switch self {
        case .text(let text):
            if let _ = URL(string: text) { // Text looks like URL? -> Copy as URL
                pasteboard.declareTypes([.URL, .string], owner: nil) // Prepare clipboard to receive string contents
                pasteboard.setString("\(self)", forType: .URL) // Put content as URL into clipboard
                pasteboard.setString("\(self)", forType: .string) // Put content as string into clipboard
            } else { // Text looks like normal text? -> Copy as normal text
                pasteboard.declareTypes([.string], owner: nil) // Prepare clipboard to receive string contents
                pasteboard.setString("\(self)", forType: .string) // Put string into clipboard
            }
        case .file:
            let pasteboardTypes: [NSPasteboard.PasteboardType] =
            if let fileURL = URL(string: "\(self)"), fileURL.pathExtension != "" { [.fileURL, .fileContentsType(forPathExtension: fileURL.pathExtension)] }
                else { [.fileURL] }
            pasteboard.declareTypes(pasteboardTypes, owner: nil) // Prepare clipboard for file
            pasteboard.setString("\(self)", forType: .fileURL) // Put content as URL into clipboard
            if let _ = URL(string: "\(self)") { pasteboard.writeFileContents("\(self)") } // Put file content into clipboard
        }
    }
}

struct ClipboardHistoryEntry: Hashable {
    var receiveDate: Date = Date() // For unique IDs in UI list
    var content: ClipboardContent
    var received: Bool // Whether the content was sent or received
}

// Send and receive clipboard contents
class ClipboardManager: ObservableObject, Equatable, WebSocketDelegate {
    @Published var connecting: Bool = false // Whether the connection is in progress
    @Published var connected: Bool = false // Whether the manager is connected to the server
    @Published var sending: Bool = false // Whether clipboard contents are being sent right now
    @Published var sendErrorMessage: String? = nil // Error message when sending the clipboard fails
    @Published var receiveErrorMessage: String? = nil // Error message when receiving the clipboard fails
    @Published var clipboardHistory: [ClipboardHistoryEntry] = []
    var receiverId: String? = nil // Needs to be set from outside because the ClipboardPortalApp does not know it, so the ContentView has to update it
    private var user: User?
    var lastReceivedContent: ClipboardContent? {
        get { clipboardHistory.filter(\.received).last?.content }
    }
    var socket: WebSocket!

    // Download clipboard content from server (and paste to text clipboard or save in Downloads)
    func downloadAndReceiveClipboardContent() async {
        guard let user = self.user else { fatalError("Missing user on ClipboardManager") }
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
    
    // Helper function for adding new clipboard content to the history and sending a notification
    private func onReceivedClipboardContent(_ content: ClipboardContent) async {
        // Copy to clipboard
        content.copyToClipboard()
        // Add to history
        DispatchQueue.main.async { self.clipboardHistory.append(ClipboardHistoryEntry(content: content, received: true)) } // Update clipboard history. Update UI in main thread.
        // Show notification (if wanted)
        await showClipboardContentNotification(content)
        // Open URLs in browser
        if case let ClipboardContent.text(textContent) = content {
            if (textContent.starts(with: "http:") || textContent.starts(with: "https:")) && !textContent.contains(" "), let url = URL(string: textContent) { // Text content looks like URL?
                NSWorkspace.shared.open(url) // Open URL in browser
            }
        }
    }

    // Start websocket connection to server to get updates for new clipboard contents
    func checkForUpdates(user: User) {
        self.user = user // Save user for WebSocket event handling later
        DispatchQueue.main.async { self.connecting = true; self.receiveErrorMessage = nil } // Reset last receive error message and mark as connecting
        var request = URLRequest(url: wsServerUrl)
        request.timeoutInterval = 10 * 365 * 24 * 60 * 60 // Wait as long as possible until clipboard content arrives
        socket = WebSocket(request: request)
        socket.delegate = self
        socket.connect()
    }
    private func retryCheckForUpdateAfterDelay() {
        guard let user = self.user else { return } // Abort if nothing to retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { // Retry connecting after Xs
            self.checkForUpdates(user: user)
        }
    }
    private struct UserAuthenticateDTO: Encodable {
        var id: String
        var secret: String
        var date: String
    }
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        DispatchQueue.main.async { self.connecting = false } // Not connecting any more when event was received
        switch event {
        case .connected(let headers):
            DispatchQueue.main.async { self.connected = true }
            print("websocket is connected: \(headers)")
            // Send authentication to receive events for new clipboard contents
            guard let user = self.user else {
                print("Cannot connect to WebSocket without user")
                return
            }
            do {
                try client.write(string: String(data: JSONEncoder().encode(UserAuthenticateDTO(id: user.id, secret: user.secret, date: (user.lastReceiveDate ?? Date.distantPast).ISO8601Format())), encoding: .utf8)!)
            } catch {
                DispatchQueue.main.async {
                    self.receiveErrorMessage = "Could not authenticate"
                    self.connected = false
                }
                self.retryCheckForUpdateAfterDelay()
            }
        case .disconnected(let reason, let code):
            print("Websocket is disconnected: \(reason) with code: \(code)")
            DispatchQueue.main.async {
                self.receiveErrorMessage = self.receiveErrorMessage ?? "Disconnected from the server" // Keep current error message or just say "Disconnected" if no detail is known
                self.connected = false
            }
            self.retryCheckForUpdateAfterDelay()
        case .text(let string):
            print("Received text: \(string)")
            if string == "new" {
                Task { await self.downloadAndReceiveClipboardContent() } // Receive new content
            } else if string == "forbidden" {
                DispatchQueue.main.async { self.receiveErrorMessage = "Could not authenticate with server. Use File > Reset User to fix this." }
            } else {
                print("Unknown text from server")
                DispatchQueue.main.async { self.receiveErrorMessage = ServerRequestError.unknown.localizedDescription }
            }
        case .binary(let data):
            print("Received data: \(data.count)")
        case .ping(_):
            break
        case .pong(_):
            break
        case .viabilityChanged(let connected):
            DispatchQueue.main.async { self.connected = connected }
            break
        case .reconnectSuggested(_):
            self.retryCheckForUpdateAfterDelay()
            break
        case .cancelled:
            DispatchQueue.main.async { self.connected = false }
            self.retryCheckForUpdateAfterDelay()
        case .error(let error):
            DispatchQueue.main.async {
                if let error, case HTTPUpgradeError.notAnUpgrade(let code, _) = error, let serverRequestErr = ServerRequestError(rawValue: code) { // Detected server error? e.g. 502
                    self.receiveErrorMessage = serverRequestErr.localizedDescription // Show user-friendly server error message
                } else {
                    self.receiveErrorMessage = error?.localizedDescription
                }
                self.connected = false
            }
            self.retryCheckForUpdateAfterDelay()
        case .peerClosed:
            DispatchQueue.main.async { self.connected = false }
            self.retryCheckForUpdateAfterDelay()
        }
    }

    // Send clipboard content to another user. Throws if there is no sendable clipboard content.
    struct ClipboardSendRequest: Encodable {
        var receiverId: String // User ID for notification
    }
    struct ClipboardSendResponse: Decodable {}
    func sendClipboardContent(_ content: ClipboardContent) async { // data -> to send, textForm -> to display in history
        print("Sending \(content)")
        guard let receiverId = self.receiverId, receiverId != "" else {
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
        body.append("\(receiverId)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body // Set request body to file upload
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("Status Code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    DispatchQueue.main.async { self.sendErrorMessage = (ServerRequestError(rawValue: httpResponse.statusCode) ?? .unknown).localizedDescription }
                }
            }

            if let responseString = String(data: data, encoding: .utf8) {
                print("Response: \(responseString)")
                DispatchQueue.main.async {
                    self.clipboardHistory.append(ClipboardHistoryEntry(content: content, received: false))
                }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            DispatchQueue.main.async { self.sendErrorMessage = error.localizedDescription }
        }
    }
    func sendClipboardContent() async {
        let pasteboard = NSPasteboard.general
        if let fileUrlString = pasteboard.propertyList(forType: .fileURL) as? String {
            guard let fileUrl = URL(string: fileUrlString) else {
                await self.sendClipboardContent(.text(fileUrlString)) // Fall back to sending the file URL if it cannot be read as a URL
                return
            }
            await self.sendClipboardContent(.file(fileUrl))
        } else if var content = pasteboard.string(forType: .string) {
            if content == "rick" { content = "https://www.youtube.com/watch?v=xvFZjo5PgG0" } // Easter egg
            await self.sendClipboardContent(.text(content))
        } else {
            DispatchQueue.main.async { self.sendErrorMessage = "No sendable clipboard content." } // Show error. Update UI in main thread.
        }
    }
    
    static func == (lhs: ClipboardManager, rhs: ClipboardManager) -> Bool {
        return lhs.sending == rhs.sending && lhs.clipboardHistory == rhs.clipboardHistory && lhs.receiverId == rhs.receiverId
    }
}
