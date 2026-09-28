// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reader",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Reader", targets: ["Reader"])],
    targets: [
        .executableTarget(name: "Reader")
    ],
    swiftLanguageModes: [.v5]
)
