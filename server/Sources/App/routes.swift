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
        return newUser // e.g. {"id":"12345678","apnsToken":"1a2b3c...","updateSecret":"1a2b3c..."}
    }
    // Update APNs token
    struct UserUpdateDTO: Content {
        var id: String
        var apnsToken: String
        var updateSecret: String
    }
    app.put { req async throws in
        let user = try req.content.decode(UserUpdateDTO.self)
        let existingUser = try await UserModel.find(user.id, on: req.db) // Find user in DB
        guard let existingUser = existingUser else { throw Abort(.notFound) } // 404 if user not found
        guard existingUser.updateSecret == user.updateSecret else { throw Abort(.unauthorized) } // 403 if update secret is incorrect
        existingUser.apnsToken = user.apnsToken // Update APNs token
        try await existingUser.save(on: req.db) // Save update to DB
        return existingUser // e.g. {"id":"12345678","apnsToken":"1a2b3c...","updateSecret":"1a2b3c..."}
    }
    // Send notification
    struct NotificationDTO: Content {
        var id: String // User ID for notification
        var clipboard: String // Clipboard contents to send
    }
    struct ClipboardPayload: Codable {
        var clipboard: String
    }
    app.post("send") { req async throws in
        let notification = try req.content.decode(NotificationDTO.self)
        let user = try await UserModel.find(notification.id, on: req.db) // Find user in DB
        guard let user = user else { throw Abort(.notFound) } // 404 if user not found
        let alert = APNSAlertNotification( // Create notification to send clipboard content to other user
            alert: .init(
                title: .raw("Received Clipboard!"),
                body: .raw(notification.clipboard)
            ),
            expiration: .immediately,
            priority: .immediately,
            topic: Environment.get("APNS_TOPIC")!, // APNs topic = bundle ID as required by Apple e.g. "com.example.app"
            payload: ClipboardPayload(clipboard: notification.clipboard) // Send clipboard contents in payload to receive them in the app and write them to the clipboard
        )
        try await req.apns.client.sendAlertNotification(alert, deviceToken: user.apnsToken) // Send notification
        return "ACK" // Acknowledge successful notification
    }
}
