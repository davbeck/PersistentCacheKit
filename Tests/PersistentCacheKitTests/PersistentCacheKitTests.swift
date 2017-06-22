import XCTest
@testable import PersistentCacheKit

class PersistentCacheKitTests: XCTestCase {
    func testExample() {
		let key = UUID()
        let cache = PersistentCache<UUID, Int>()
		
		cache[key] = 5
		
		let expectation = self.expectation(description: "Clear memory cache")
		cache.clearMemoryCache() {
			expectation.fulfill()
		}
		self.wait(for: [expectation], timeout: 5)
		
		XCTAssertEqual(cache[key], 5)
    }
	
	func testNamespaces() {
		let key = UUID()
		
		let cacheA = PersistentCache<UUID, Int>(namespace: "A")
		let cacheB = PersistentCache<UUID, Int>(namespace: "B")
		
		cacheA[key] = 5
		cacheB[key] = 10
		
		self.wait(for: [cacheA, cacheB].map({ cache in
			let expectation = self.expectation(description: "Clear memory cache")
			cache.clearMemoryCache() {
				expectation.fulfill()
			}
			return expectation
		}), timeout: 5)
		
		XCTAssertEqual(cacheA[key], 5)
		XCTAssertEqual(cacheB[key], 10)
	}
	
	func testTrim() {
		do {
			var url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			url.appendPathComponent("PersistentCacheKitTests")
			url.appendPathComponent(UUID().uuidString)
			url.appendPathComponent("storage.sqlite")
			print("test url: \(url.path)")
			let storage = try SQLiteCacheStorage(url: url)
			let cache = PersistentCache<UUID, Data>(storage: storage)
			
			let testData = Data((0..<1024).map({ UInt8(extendingOrTruncating: $0) }))
			for _ in 0..<150 {
				cache[UUID()] = testData
			}
			_ = cache[UUID()] // make sure all changes are written out
			
			storage.maxFilesize = 100 * 1024
			try storage.trimFilesize()
			
			let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
			XCTAssertLessThan(fileSize, storage.maxFilesize!)
			
			
			try FileManager.default.removeItem(at: url)
		} catch {
			XCTFail("error was thrown: \(error)")
		}
	}
	
	
    static var allTests = [
        ("testExample", testExample),
    ]
}
