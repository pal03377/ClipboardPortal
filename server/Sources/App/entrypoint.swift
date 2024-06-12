import Vapor
import Fluent
import FluentSQLiteDriver
import Logging

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = try await Application.make(env)
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
            let dbPath = "data/db.sqlite"
            if !FileManager.default.fileExists(atPath: dbPath) { FileManager.default.createFile(atPath: dbPath, contents: nil, attributes: nil) }
            app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)
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
