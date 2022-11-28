// swift-tools-version:5.7
import PackageDescription

let package = Package(
	name: "PersistentCacheKit",
	platforms: [
		.macOS(.v10_15),
		.iOS(.v13),
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
			dependencies: ["PersistentCacheKit"]
		),
	]
)
