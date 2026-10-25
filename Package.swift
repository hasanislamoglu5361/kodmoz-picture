// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KodmozPicture",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KodmozPicture", targets: ["KodmozPicture"])
    ],
    targets: [
        .executableTarget(
            name: "KodmozPicture",
            path: "Sources/KodmozPicture",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ]
)
