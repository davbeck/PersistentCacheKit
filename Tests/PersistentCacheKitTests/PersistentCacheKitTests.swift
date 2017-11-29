import XCTest
@testable import PersistentCacheKit


struct Thing: Codable, Equatable {
	var a: String = (0..<10).map({ String(arc4random_uniform($0 * 2)) }).joined()
	var b: Int = Int(arc4random())
	var c: Bool = arc4random_uniform(2) == 0
	
	static func ==(lhs: Thing, rhs: Thing) -> Bool {
		return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c
	}
}


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
	
	func testPerformance() {
		let cache = PersistentCache<Int, Thing>()
		
		let things = (0..<1000).map({ _ in Thing() })
		measure {
			for (key, thing) in zip(things.indices, things) {
				cache[key] = thing
			}
			
			let expectation = self.expectation(description: "Clear memory cache")
			cache.clearMemoryCache() {
				expectation.fulfill()
			}
			self.wait(for: [expectation], timeout: 5)
			
			for (key, thing) in zip(things.indices, things) {
				XCTAssertEqual(cache[key], thing)
			}
		}
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
			
			let testData = Data((0..<1024).map({ UInt8(clamping: $0) }))
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
