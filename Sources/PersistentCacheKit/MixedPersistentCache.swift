import Foundation
import Combine
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

public class MixedPersistentCache {
	private let queue = DispatchQueue(label: "Cache", attributes: .concurrent)
	private var internalCache = [String: Any]()

	public let storage: CacheStorage?
	public let namespace: String?
	public let encoder = PropertyListEncoder()
	public let decoder = PropertyListDecoder()

	public init(storage: CacheStorage? = SQLiteCacheStorage.shared, namespace: String? = nil) {
		self.storage = storage
		self.namespace = namespace

		#if os(iOS)
			NotificationCenter.default.addObserver(self, selector: #selector(self.didReceiveMemoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
		#endif
	}

	@objc private func didReceiveMemoryWarning() {
		self.clearMemoryCache()
	}

	public func clearMemoryCache(completion: (() -> Void)? = nil) {
		self.queue.async(flags: .barrier) {
			self.internalCache = [:]

			if let completion = completion {
				DispatchQueue.global().async {
					completion()
				}
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

	private let updated = PassthroughSubject<(key: String, value: Any?), Never>()

	public func updates<Value>(for key: Key<Value>) -> some Publisher<Value?, Never> {
		updated
			.filter { $0.key == key.rawValue }
			.map { $0.value as? Value }
	}
	
	public func publisher<Value>(for key: Key<Value>) -> some Publisher<Value?, Never> {
		updates(for: key)
			.prepend(self[key])
	}

	public subscript<Value>(key: Key<Value>) -> Value? {
		get {
			if let item = self[item: key], item.isValid {
				return item.value
			} else {
				return nil
			}
		}
		set {
			self[item: key] = newValue.map { Item($0) }
		}
	}

	public subscript<Value>(item key: Key<Value>) -> Item<Value>? {
		get {
			self.queue.sync {
				if let item = self.internalCache[stringKey(for: key)] as? Item<Value> {
					return item
				} else if let data = self.storage?[stringKey(for: key)], let item = try? self.decoder.decode(Item<Value>.self, from: data) {
					return item
				} else {
					return nil
				}
			}
		}
		set {
			let data = try? self.encoder.encode(newValue)

			self.queue.async(flags: .barrier) {
				self.internalCache[self.stringKey(for: key)] = newValue

				self.storage?[self.stringKey(for: key)] = data

				DispatchQueue.global().async {
					self.updated.send((key.rawValue, newValue?.value))
				}
			}
		}
	}

	/// Find a value or generate it if one doesn't exist.
	///
	/// If a value for the given key does not already exist in the cache, the fallback value will be used instead and saved for later use.
	///
	/// - Parameters:
	///   - key: The key to lookup.
	///   - fallback: The value to use if a value for the key does not exist.
	/// - Returns: Either an existing cached value or the result of fallback.
	public func fetch<Value>(_ key: Key<Value>, fallback: () -> Value) -> Value {
		if let value = self[key] {
			return value
		} else {
			let value = fallback()
			self[key] = value
			return value
		}
	}

	private func _fetch<Value>(_ key: Key<Value>, queue: DispatchQueue = .main, fallback: (() -> Value)?, completion: @escaping (Value?) -> Void) {
		self.queue.sync {
			if let item = self.internalCache[stringKey(for: key)] as? Item<Value>, item.isValid {
				completion(item.value)
			} else {
				self.queue.async {
					if let data = self.storage?[self.stringKey(for: key)], let item = try? self.decoder.decode(Item<Value>.self, from: data) {
						queue.async {
							completion(item.value)
						}
					} else {
						queue.async {
							if let value = fallback?() {
								self[key] = value

								completion(value)
							} else {
								completion(nil)
							}
						}
					}
				}
			}
		}
	}

	/// Asynchronously fetches data from the filesystem.
	///
	/// This method will sychronously check the in memory cache for the value and call completion immediately if a value is found. Otherwise it will asynchrounously check the filesystem on a background queue. Finally, if no value exists it will call the fallback block and save the returned value to the cache.
	///
	/// - Parameters:
	///   - key: The key to lookup.
	///   - queue: The queue that the completion and fallback blocks will be called on.
	///   - fallback: The value to use if a value for the key does not exist.
	///   - completion: The block to call when a result is found. This will always be called.
	public func fetch<Value>(_ key: Key<Value>, queue _: DispatchQueue = .main, fallback: @escaping () -> Value, completion: @escaping (Value) -> Void) {
		self._fetch(key, fallback: fallback) { completion($0!) }
	}

	/// Asynchronously fetches data from the filesystem.
	///
	/// This method will sychronously check the in memory cache for the value and call completion immediately if a value is found. Otherwise it will asynchrounously check the filesystem on a background queue.
	///
	/// - Parameters:
	///   - key: The key to lookup.
	///   - queue: The queue that the completion block will be called on.
	///   - completion: The block to call when a result is found. This will always be called.
	public func fetch<Value>(_ key: Key<Value>, queue _: DispatchQueue = .main, completion: @escaping (Value?) -> Void) {
		self._fetch(key, fallback: nil, completion: completion)
	}

	/// Wait until all operations have been completed and data has been saved.
	public func sync() {
		queue.sync {}
		self.storage?.sync()
	}
}
