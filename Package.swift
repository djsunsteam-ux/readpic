// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Readpic",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Readpic", targets: ["Readpic"])
    ],
    targets: [
        .executableTarget(
            name: "Readpic",
            path: "Readpic",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("TESTING", .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "ReadpicTests",
            dependencies: ["Readpic"],
            path: "Tests/ReadpicTests"
        )
    ]
)
