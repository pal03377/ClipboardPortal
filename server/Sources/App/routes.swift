import Vapor

extension UserModel: Content {} // Allow sending the UserModel directly in the response

func routes(_ app: Application) throws {
    // Create new user
    struct UserCreateDTO: Content {}
    app.post { req async throws in
        // let user = try req.content.decode(UserCreateDTO.self) // Currently not needed because there is request data
        let newUser = UserModel() // Create new user
        try await newUser.save(on: req.db) // Save new user to DB
        return newUser // e.g. {"id":"12345678","secret":"1a2b3c..."}
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
    app.on(.POST, "send", body: .collect(maxSize: "30mb")) { req async throws in // Increase max size to X MB for larger clipboard contents
        print("Body: " + (req.body.string ?? "No body")) // Print incoming data for debugging
        var notification = try req.content.decode(ClipboardContentSendDTO.self)
        let user = try await UserModel.find(notification.receiverId, on: req.db) // Find user in DB
        guard let user = user else { throw Abort(.notFound) } // 404 if user not found
        // Set ID for clipboard content
        notification.clipboardContent.id = UUID()
        // Store original clipboard content in DB to be able to retrieve it later
        user.lastReceivedClipboardContent = notification.clipboardContent
        try await user.save(on: req.db)
        return ClipboardSendResponse(id: notification.clipboardContent.id!) // e.g. {"id":"123e4567-e89b-12d3-a456-426614174000"}
    }
    // Receive clipboard content
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
