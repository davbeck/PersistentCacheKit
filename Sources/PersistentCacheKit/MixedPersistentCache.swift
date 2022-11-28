import Foundation
import AsyncAlgorithms
#if os(iOS)
	import UIKit
#endif

public struct Key<Value: Codable>: Hashable, RawRepresentable {
	public var rawValue: String

	public init(rawValue: String) {
		self.rawValue = rawValue
	}

	public init(_ rawValue: String) {
		self.rawValue = rawValue
	}
}

public actor MixedPersistentCache {
	private var internalCache = [String: Any]()

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

	public func clearMemoryCache(completion: (() -> Void)? = nil) {
		self.internalCache = [:]

		if let completion = completion {
			DispatchQueue.global().async {
				completion()
			}
		}
	}

	private func stringKey<Value>(for key: Key<Value>) -> String {
		if let namespace = namespace {
			return namespace + key.rawValue
		} else {
			return key.rawValue
		}
	}

	private let cacheUpdated = AsyncChannel<(key: String, value: Any?)>()
	// TODO: switch to some AsyncSequence<Value?> when available
	func updates<Value>(for key: Key<Value>) -> AsyncMapSequence<AsyncFilterSequence<AsyncChannel<(key: String, value: Any?)>>, Value?> {
		cacheUpdated
			.filter { $0.key == key.rawValue }
			.map { $0.value as? Value }
	}

	public func get<Value>(_ key: Key<Value>) async -> Value? {
		if let item = await self.get(item: key), item.isValid {
			return item.value
		} else {
			return nil
		}
	}

	public func set<Value>(_ key: Key<Value>, _ newValue: Value?) async {
		await self.set(key, newValue.map { Item($0) })
	}

	public func get<Value>(item key: Key<Value>) async -> Item<Value>? {
		if let item = self.internalCache[key.rawValue] as? Item<Value> {
			return item
		} else if
			let data = await self.storage?.get(stringKey(for: key)),
			let item = try? self.decoder.decode(Item<Value>.self, from: data)
		{
			return item
		} else {
			return nil
		}
	}

	public func set<Value>(_ key: Key<Value>, _ item: Item<Value>?) async {
		self.internalCache[key.rawValue] = item

		await self.cacheUpdated.send((key.rawValue, item?.value))

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
	public func get<Value>(
		_ key: Key<Value>,
		fallback: () async -> Value
	) async -> Value {
		if let value = await self.get(key) {
			return value
		} else {
			let value = await fallback()
			await self.set(key, value)
			return value
		}
	}
}
