import Vapor
import APNSCore

extension UserModel: Content {} // Allow sending the UserModel directly in the response

func routes(_ app: Application) throws {
    // Create new user
    struct UserCreateDTO: Content {
        var apnsToken: String
    }
    app.post { req async throws in
        let user = try req.content.decode(UserCreateDTO.self)
        let newUser = UserModel(apnsToken: user.apnsToken) // Create new user
        try await newUser.save(on: req.db) // Save new user to DB
        return newUser // e.g. {"id":"12345678","apnsToken":"1a2b3c...","secret":"1a2b3c..."}
    }
    // Update APNs token
    struct UserUpdateDTO: Content {
        var id: String
        var apnsToken: String
        var secret: String
    }
    app.put { req async throws in
        let user = try req.content.decode(UserUpdateDTO.self)
        let existingUser = try await UserModel.find(user.id, on: req.db) // Find user in DB
        guard let existingUser = existingUser else { throw Abort(.notFound) } // 404 if user not found
        guard existingUser.secret == user.secret else { throw Abort(.unauthorized) } // 403 if update secret is incorrect
        existingUser.apnsToken = user.apnsToken // Update APNs token
        try await existingUser.save(on: req.db) // Save update to DB
        return existingUser // e.g. {"id":"12345678","apnsToken":"1a2b3c...","secret":"1a2b3c..."}
    }
    // Send notification
    struct ClipboardContentSendDTO: Content {
        var receiverId: String // User ID for notification
        var clipboardContent: ClipboardContent // Clipboard contents to send
    }
    struct ClipboardPayload: Codable {
        var clipboardContent: ClipboardContent
        var date: Date
    }
    struct ClipboardSendResponse: Content {
        var id: UUID // ID of the clipboard content
    }
    app.post("send") { req async throws in
        print("Body: " + (req.body.string ?? "No body")) // Print incoming data for debugging
        var notification = try req.content.decode(ClipboardContentSendDTO.self)
        let user = try await UserModel.find(notification.receiverId, on: req.db) // Find user in DB
        guard let user = user else { throw Abort(.notFound) } // 404 if user not found
        print("Topic: " + Environment.get("APNS_TOPIC")!) // Print APNs topic for debugging
        // Set ID from server
        notification.clipboardContent.id = UUID() // Set ID from server
        // Truncate clipboard content because of APNs payload size limit (4KB - https://stackoverflow.com/a/26994198/4306257)
        let clipboardContentTruncated = notification.clipboardContent.truncated() // Truncate clipboard content because of APNs payload size limit (4KB - https://stackoverflow.com/a/26994198/4306257)
        // Store original clipboard content in DB to be able to retrieve it later
        user.lastReceivedClipboardContent = notification.clipboardContent
        try await user.save(on: req.db)
        // Send notification to user
        let alert: APNSAlertNotification<ClipboardPayload> = APNSAlertNotification( // Create notification to send clipboard content to other user
            alert: .init(
                title: .raw("Received Clipboard!"),
                body: .raw(clipboardContentTruncated.content)
            ),
            expiration: .timeIntervalSince1970InSeconds(Int(Date().timeIntervalSince1970 + 30)), // Expire in X seconds
            priority: .immediately,
            topic: Environment.get("APNS_TOPIC")!, // APNs topic = bundle ID as required by Apple e.g. "com.example.app"
            payload: ClipboardPayload(clipboardContent: clipboardContentTruncated, date: Date()), // Send clipboard contents in payload to receive them in the app and write them to the clipboard
            sound: .default,
            interruptionLevel: .timeSensitive
        )
        print(alert) // Print alert for debugging
        do {
            print("Sending to device token \(user.apnsToken)")
            let resp = try await req.apns.client.sendAlertNotification(alert, deviceToken: user.apnsToken) // Send notification
            print("Response: \(resp) (cannot use apns-id to check status because it is not the apns-unique-id :( )")
            print("Unique ID: \(resp.apnsUniqueID?.description.lowercased() ?? "nil")") // Print unique ID for debugging
        } catch {
            print("Error sending notification: \(error)") // Print error for debugging
            throw Abort(.internalServerError) // 500 if error sending notification
        }
        return ClipboardSendResponse(id: notification.clipboardContent.id!) // e.g. {"id":"123e4567-e89b-12d3-a456-426614174000"}
    }
    // Receive full clipboard content
    struct ClipboardContentReceiveDTO: Content {
        var id: String
        var secret: String
        var skipForId: UUID? // Skip sending for clipboard content ID to avoid too much traffic
    }
    struct ClipboardContentReceiveResponse: Content {
        var clipboardContent: ClipboardContent?
    }
    app.post("receive") { req async throws in
        let receivedData = try req.content.decode(ClipboardContentReceiveDTO.self)
        let user = try await UserModel.find(receivedData.id, on: req.db) // Find user in DB
        guard let user = user else { throw Abort(.notFound) } // 404 if user not found
        guard user.secret == receivedData.secret else { throw Abort(.unauthorized) } // 403 if secret is incorrect
        if user.lastReceivedClipboardContent?.id == receivedData.skipForId { // Skip sending clipboard content that the client already has
            return ClipboardContentReceiveResponse(clipboardContent: nil) // e.g. {"clipboardContent":nil}
        }
        return ClipboardContentReceiveResponse(clipboardContent: user.lastReceivedClipboardContent) // e.g. {"clipboardContent":"Hello, World!"} or {"clipboardContent":nil}
    }
}
