// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeAlfred",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WeAlfred", targets: ["WeAlfred"])],
    targets: [
        .executableTarget(name: "WeAlfred"),
        .testTarget(name: "WeAlfredTests", dependencies: ["WeAlfred"]),
    ]
)
