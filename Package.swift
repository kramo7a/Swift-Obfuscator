// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftObfuscator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "swift-obfuscator", targets: ["SwiftObfuscator"]),
        .library(name: "ObfuscatorCore", targets: ["ObfuscatorCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/indexstore-db.git", branch: "release/6.2")
    ],
    targets: [
        .target(
            name: "ObfuscatorCore",
            dependencies: [
                .product(name: "IndexStoreDB", package: "indexstore-db")
            ]
        ),
        .executableTarget(
            name: "SwiftObfuscator",
            dependencies: ["ObfuscatorCore"]
        ),
        .testTarget(
            name: "ObfuscatorCoreTests",
            dependencies: ["ObfuscatorCore"]
        )
    ],
    cxxLanguageStandard: .cxx17
)
