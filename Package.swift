// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tuck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tuck", path: "Sources/Tuck")
    ]
)
