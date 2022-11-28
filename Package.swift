// swift-tools-version: 5.7
import PackageDescription

let package = Package(
	name: "PersistentCacheKit",
	platforms: [
		.macOS(.v10_15),
		.iOS(.v15),
	],
	products: [
		.library(
			name: "PersistentCacheKit",
			targets: ["PersistentCacheKit"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-async-algorithms", from: "0.0.3"),
	],
	targets: [
		.target(
			name: "PersistentCacheKit",
			dependencies: [
				.product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
			]
		),
		.testTarget(
			name: "PersistentCacheKitTests",
			dependencies: ["PersistentCacheKit"]
		),
	]
)
