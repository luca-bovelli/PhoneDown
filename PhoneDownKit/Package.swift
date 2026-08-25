// swift-tools-version: 6.0
import PackageDescription

// PhoneDownKit is deliberately free of UIKit, SwiftUI and ActivityKit so that
// the whole domain — scheduling, accumulation, statistics — compiles and tests
// on the CI host in seconds without booting a simulator. Every iteration here is
// a CI round trip, so the fast lane matters.
let package = Package(
    name: "PhoneDownKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PhoneDownKit", targets: ["PhoneDownKit"]),
    ],
    targets: [
        .target(
            name: "PhoneDownKit",
            path: "Sources/PhoneDownKit"
        ),
        .testTarget(
            name: "PhoneDownKitTests",
            dependencies: ["PhoneDownKit"],
            path: "Tests/PhoneDownKitTests"
        ),
    ]
)
