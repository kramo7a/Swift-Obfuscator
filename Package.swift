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
        .package(url: "https://github.com/swiftlang/indexstore-db.git", branch: "release/6.2"),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            revision: "050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf"
        )
    ],
    targets: [
        .target(
            name: "ObfuscatorCore",
            dependencies: [
                .product(name: "IndexStoreDB", package: "indexstore-db"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
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
