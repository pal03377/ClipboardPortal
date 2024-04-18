import Vapor
import Fluent
import FluentSQLiteDriver
import APNS
import VaporAPNS
import APNSCore
import Logging

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = Application(env)
        defer { app.shutdown() }
        
        do {
            // Serve files from /Public folder
            app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
            // Set up database
            app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
            // Create tables
            app.migrations.add(CreateUser())
            try await app.autoMigrate() // Run migrations
            // Register routes
            try routes(app)
            // Set up APNS for notifications
            let apnsConfig = APNSClientConfiguration(
                authenticationMethod: .jwt(
                    privateKey: try .loadFrom(string: Environment.get("APNS_P8_CONTENT")!.replacingOccurrences(of: "\\n", with: "\n")),
                    keyIdentifier: Environment.get("APNS_KEY_ID")!,
                    teamIdentifier: Environment.get("APNS_TEAM_ID")!
                ),
                environment: Environment.get("APNS_ENVIRONMENT") == "production" ? .production : .sandbox
            )
            app.apns.containers.use(
                apnsConfig,
                eventLoopGroupProvider: .shared(app.eventLoopGroup),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder(),
                as: .default
            )
        } catch {
            app.logger.report(error: error)
            throw error
        }
        try await app.execute()
    }
}
