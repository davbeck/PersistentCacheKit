import Foundation
#if os(iOS)
	import UIKit
#endif

public protocol CacheStorage: AnyObject {
	func get(_ key: String) async -> Data?
	func set(_ key: String, value newValue: Data?) async
}

extension CacheStorage {
	func sync() {}
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

public actor PersistentCache<Key: CustomStringConvertible & Hashable, Value: Codable> {
	private var internalCache = [Key: Item<Value>]()

	public let storage: CacheStorage?
	public let namespace: String?
	public let encoder = PropertyListEncoder()
	public let decoder = PropertyListDecoder()

	#if os(iOS)
		private var memoryWarningTask: Task<Void, Never>?

		deinit {
			memoryWarningTask?.cancel()
		}
	#endif

	public init(storage: CacheStorage? = SQLiteCacheStorage.shared, namespace: String? = nil) {
		self.storage = storage
		self.namespace = namespace

		#if os(iOS)
			Task { [weak self] in
				let publisher = await NotificationCenter.default.publisher(
					for: UIApplication.didReceiveMemoryWarningNotification,
					object: nil
				)
				for await _ in publisher.values {
					guard let self else { throw CancellationError() }
					await self.clearMemoryCache()
				}
			}
		#endif
	}

	public func clearMemoryCache() {
		self.internalCache = [:]
	}

	private func stringKey(for key: Key) -> String {
		if let namespace = namespace {
			return namespace + key.description
		} else {
			return key.description
		}
	}

	public func get(_ key: Key) async -> Value? {
		if let item = await self.get(item: key), item.isValid {
			return item.value
		} else {
			return nil
		}
	}

	public func set(_ key: Key, _ newValue: Value?) async {
		await self.set(key, newValue.map { Item($0) })
	}

	public func get(item key: Key) async -> Item<Value>? {
		if let item = self.internalCache[key] {
			return item
		} else if let data = await self.storage?.get(self.stringKey(for: key)), let item = try? self.decoder.decode(Item<Value>.self, from: data) {
			return item
		} else {
			return nil
		}
	}

	public func set(_ key: Key, _ item: Item<Value>?) async {
		self.internalCache[key] = item

		let data = await Task { try? self.encoder.encode(item) }.value
		
		await self.storage?.set(self.stringKey(for: key), value: data)
	}

	/// Find a value or generate it if one doesn't exist.
	///
	/// If a value for the given key does not already exist in the cache, the fallback value will be used instead and saved for later use.
	///
	/// - Parameters:
	///   - key: The key to lookup.
	///   - fallback: The value to use if a value for the key does not exist.
	/// - Returns: Either an existing cached value or the result of fallback.
	public func get(_ key: Key, fallback: () async -> Value) async -> Value {
		if let value = await self.get(key) {
			return value
		} else {
			let value = await fallback()
			await self.set(key, value)
			return value
		}
	}
}
