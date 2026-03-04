// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacDjView",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacDjView",
            path: "Sources/MacDjView",
            resources: [
                .process("Assets.xcassets"),
                .copy("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
