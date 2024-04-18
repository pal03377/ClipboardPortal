// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "server",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.4"), // Vapor - Server framework
        .package(url: "https://github.com/vapor/fluent.git", from: "4.6.0"), // Fluent - DB framework
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.6.0"), // SQLite driver for Fluent
        .package(url: "https://github.com/vapor/apns.git", from: "4.0.0"), // APNs library for push notifications
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "VaporAPNS", package: "apns"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableExperimentalFeature("StrictConcurrency"),
] }
