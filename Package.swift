// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GitignoreClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "GitignoreClaimKit", targets: ["GitignoreClaimKit"]),
        .executable(name: "GitignoreClaimDemo", targets: ["GitignoreClaimDemo"])
    ],
    targets: [
        .target(name: "GitignoreClaimKit"),
        .executableTarget(
            name: "GitignoreClaimDemo",
            dependencies: ["GitignoreClaimKit"]
        ),
        .testTarget(
            name: "GitignoreClaimKitTests",
            dependencies: ["GitignoreClaimKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
