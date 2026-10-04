// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuTint",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MenuTint",
            path: "Sources/MenuTint"
        )
    ]
)
