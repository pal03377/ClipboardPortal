import Vapor
import Fluent
import FluentSQLiteDriver
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
            // Create data dir if it doesn't exist
            let dataDir = app.directory.workingDirectory + "data"
            if !FileManager.default.fileExists(atPath: dataDir) {
                try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true, attributes: nil)
            }
            // Set up database
            app.databases.use(.sqlite(.file("data/db.sqlite")), as: .sqlite)
            // Create tables
            app.migrations.add(CreateUser())
            try await app.autoMigrate() // Run migrations
            // Register routes
            try routes(app)
        } catch {
            app.logger.report(error: error)
            throw error
        }
        try await app.execute()
    }
}
