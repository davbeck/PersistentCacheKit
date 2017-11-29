// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PersistentCacheKit",
    products: [
        .library(
            name: "PersistentCacheKit",
            targets: ["PersistentCacheKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PersistentCacheKit",
            dependencies: []),
        .testTarget(
            name: "PersistentCacheKitTests",
            dependencies: []),
    ]
)
