import Foundation


public protocol CacheStorage: class {
	subscript(key: String) -> Data? { get set }
}


public struct Item<Value: Codable>: Codable {
	public var expiration: Date?
	public var value: Value
	
	public var isValid: Bool {
		if let expiration = expiration {
			return expiration.timeIntervalSinceNow >= 0
		} else {
			return true
		}
	}
	
	public init(_ value: Value, expiration: Date? = nil) {
		self.value = value
		self.expiration = expiration
	}
	
	public init(_ value: Value, expiresIn: TimeInterval) {
		self.init(value, expiration: Date(timeIntervalSinceNow: expiresIn))
	}
}


public class PersistentCache<Key: CustomStringConvertible & Hashable, Value: Codable> {
	private let queue = DispatchQueue(label: "Cache", attributes: .concurrent)
	private var internalCache = Dictionary<Key, Item<Value>>()
	
	public let storage: CacheStorage?
	public let namespace: String?
	public let encoder = PropertyListEncoder()
	public let decoder = PropertyListDecoder()
	
	public init(storage: CacheStorage? = SQLiteCacheStorage.shared, namespace: String? = nil) {
		self.storage = storage
		self.namespace = namespace
		
		#if os(iOS)
			NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMemoryWarning), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
		#endif
	}
	
	
	@objc private func didReceiveMemoryWarning() {
		self.clearMemoryCache()
	}
	
	public func clearMemoryCache(completion: (() -> Void)? = nil) {
		queue.async(flags: .barrier) {
			self.internalCache = [:]
			
			if let completion = completion {
				DispatchQueue.global().async {
					completion()
				}
			}
		}
	}
	
	
	private func stringKey(for key: Key) -> String {
		if let namespace = namespace {
			return namespace + key.description
		} else {
			return key.description
		}
	}
	
	public subscript(key: Key) -> Value? {
		get {
			if let item = self[item: key], item.isValid {
				return item.value
			} else {
				return nil
			}
		}
		set {
			self[item: key] = newValue.map({ Item($0) })
		}
	}
	
	public subscript(item key: Key) -> Item<Value>? {
		get {
			return queue.sync {
				if let item = self.internalCache[key] {
					return item
				} else if let data = self.storage?[self.stringKey(for: key)], let item = try? self.decoder.decode(Item<Value>.self, from: data) {
					return item
				} else {
					return nil
				}
			}
		}
		set {
			let data = try? self.encoder.encode(newValue)
			
			queue.async(flags: .barrier) {
				self.internalCache[key] = newValue
				
				self.storage?[self.stringKey(for: key)] = data
			}
		}
	}
}
