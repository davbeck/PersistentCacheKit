@testable import PersistentCacheKit
import XCTest

struct Thing: Codable, Equatable {
	var a: String = (0..<10).map { String(arc4random_uniform($0 * 2)) }.joined()
	var b: Int = .init(arc4random())
	var c: Bool = arc4random_uniform(2) == 0
	
	static func == (lhs: Thing, rhs: Thing) -> Bool {
		return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c
	}
}

class PersistentCacheKitTests: XCTestCase {
	var cacheStorage: SQLiteCacheStorage!
	let url = FileManager.default.temporaryDirectory
		.appendingPathComponent(UUID().uuidString)
		.appendingPathComponent("cache")
		.appendingPathExtension("sqlite")
	
	override func setUp() {
		super.setUp()
		
		self.cacheStorage = try! SQLiteCacheStorage(url: self.url)
	}
	
	override func tearDown() {
		super.tearDown()
		
		self.cacheStorage = nil
	}
	
	// MARK: - Tests
	
	func testExample() async {
		let key = UUID()
		let cache = PersistentCache<UUID, Int>(storage: cacheStorage)
		
		await cache.set(key, 5)
		
		await cache.clearMemoryCache()
		
		let value = await cache.get(key)
		XCTAssertEqual(value, 5)
	}
	
	func testMultipleStores() async throws {
		let key = UUID()
		let cache = PersistentCache<UUID, Int>(storage: cacheStorage)
		
		await cache.set(key, 5)
		
		let otherCacheStorage = try SQLiteCacheStorage(url: url)
		let otherCache = PersistentCache<UUID, Int>(storage: otherCacheStorage)
		
		let value = await otherCache.get(key)
		XCTAssertEqual(value, 5)
	}
	
	func test_getFallback() async {
		let cache = PersistentCache<UUID, Int>(storage: cacheStorage)
		let key = UUID()
		
		let result = await cache.get(key, fallback: { 10 })
		XCTAssertEqual(result, 10)
		let value = await cache.get(key)
		XCTAssertEqual(value, 10)
	}
	
	func test_getFallback_existingValue() async {
		let cache = PersistentCache<UUID, Int>(storage: cacheStorage)
		let key = UUID()
		
		await cache.set(key, 5)
		
		let result = await cache.get(key, fallback: { 10 })
		XCTAssertEqual(result, 5)
	}
	
	func testMemoryCache() async {
		let key = UUID()
		let cache1 = PersistentCache<UUID, Int>(storage: nil)
		let cache2 = PersistentCache<UUID, Int>(storage: nil)
		
		await cache1.set(key, 5)
		await cache2.set(key, 6)
		
		let value1 = await cache1.get(key)
		XCTAssertEqual(value1, 5)
		let value2 = await cache2.get(key)
		XCTAssertEqual(value2, 6)
	}
	
//	func testPerformance() async {
//		let cache = PersistentCache<Int, Thing>(storage: cacheStorage)
//
//		let things = (0..<100).map { _ in Thing() }
//		measure {
//			for (key, thing) in zip(things.indices, things) {
//				await cache.set(key, value: thing)
//			}
//
//			let expectation = self.expectation(description: "Clear memory cache")
//			cache.clearMemoryCache {
//				expectation.fulfill()
//			}
//			self.wait(for: [expectation], timeout: 5)
//
//			for (key, thing) in zip(things.indices, things) {
//				XCTAssertEqual(cache[key], thing)
//			}
//		}
//	}
	
	func testNamespaces() async {
		let key = UUID()
		
		let cacheA = PersistentCache<UUID, Int>(storage: cacheStorage, namespace: "A")
		let cacheB = PersistentCache<UUID, Int>(storage: cacheStorage, namespace: "B")
		
		await cacheA.set(key, 5)
		await cacheB.set(key, 10)
		
		await cacheA.clearMemoryCache()
		await cacheB.clearMemoryCache()
		
		let valueA = await cacheA.get(key)
		XCTAssertEqual(valueA, 5)
		let valueB = await cacheB.get(key)
		XCTAssertEqual(valueB, 10)
	}
	
	func testTrim() async {
		do {
			var url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			url.appendPathComponent("PersistentCacheKitTests")
			url.appendPathComponent(UUID().uuidString)
			url.appendPathComponent("storage.sqlite")
			let storage = try SQLiteCacheStorage(url: url)
			let cache = PersistentCache<UUID, Data>(storage: storage)
			
			let testData = Data((0..<1024).map { UInt8(clamping: $0) })
			for _ in 0..<150 {
				await cache.set(UUID(), testData)
			}
			
			await storage.setMaxFilesize(100 * 1024)
			try await storage.trimFilesize()
			
			let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
			let maxFilesize = await storage.maxFilesize
			XCTAssertLessThan(fileSize, try XCTUnwrap(maxFilesize))
			
			try FileManager.default.removeItem(at: url)
		} catch {
			XCTFail("error was thrown: \(error)")
		}
	}
}
