// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tasktarrasque",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Tasktarrasque",
            path: "Sources/Tasktarrasque"
        )
    ]
)
