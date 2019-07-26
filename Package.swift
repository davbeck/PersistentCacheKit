// swift-tools-version:5.0
import PackageDescription

let package = Package(
	name: "PersistentCacheKit",
	platforms: [
		.macOS(.v10_10),
		.iOS(.v10),
	],
	products: [
		.library(
			name: "PersistentCacheKit",
			targets: ["PersistentCacheKit"]
		),
	],
	dependencies: [],
	targets: [
		.target(
			name: "PersistentCacheKit",
			dependencies: []
		),
		.testTarget(
			name: "PersistentCacheKitTests",
			dependencies: []
		),
	]
)
