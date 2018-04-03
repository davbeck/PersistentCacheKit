# PersistentCacheKit

A Swift library for caching items to the filesystem (using SQLite by default).

A `PersistentCache` is a view into a cache storage that uses specifically typed keys and values. It will use an in memory cache for fast access of commonly used data. And because the memory cache is type specific, it can be even faster than a more general cache implimentation.

`PersistentCache` optionally has a `CacheStorage` that it uses to persist it's data accross app launches, or even accross memory warnings. By default this is set to the shared `SQLiteCacheStorage`. Persistent storage converts all keys to strings and all values to data using `Codable`.

### Concurrency

Caches and storages are thread safe. Each cache uses it's own serial queue, so that different caches can operate independently of each other while remaining internally consistent. When a cache only needs to access it's in memory store, it can do so in parallel with other caches. When it needs to access a store it will do so serially. As much work is done asynchronously as possible. For instance, when setting a new value the memory cache is updated immidiately so that subsequent request for that data will be correct, but is asynchronously written to disk.

## Usage

```swift
struct Message: Codable {
	var id: UUID = UUID()
	var createdAt: Date = Date()
	var body: String = ""
}

let cache = PersistentCache<UUID, [Message]>()
let roomID = UUID()
if let cached = cache[roomID] {
	// show cached messages
} else {
	// load them some expensive way
	cache[roomID] = (0..<10).map({ Message(body: String($0)) })
}
```

### Creating a cache:

Often you only need to specify the key and value types. However you can also include a cache storage and namespace:

```swift
let cache = PersistentCache<UUID, [Message]>(storage: customStorage, namespace: "com.example.app")
```

Using custom storage can be useful either to use a different storage method or to parallize storage between caches.

A namespace is very useful to avoid name collisions between multiple caches.

### Access values

The simplest way to access cache data is to use subscripts.

```swift
let value = cache[key]
cache[key] = value
```

This will use the memory cache if possible, or access storage if needed.

You can also access data using cache items:

```swift
let value = cache[item: key]
cache[item: key] = Item(value, expiresIn: 60 * 60)
```

This is mostly valuable to set an expiration date for the value. Regular subscript will ignore an expired item, so in practice it should be rare that you need to get an item directly.

Various fetch metohds exist to do a find or update on the cache:

```swift
cache.fetch(key, fallback: { value })
```

This is a basic wrapper around subscript access. The other fetch methods perform lookup asynchronously:

```swift
cache.fetch(key, queue: .main) { value in
	// use value (possibly nil)
}

cache.fetch(key, queue: .main, fallback: { value }) { value in
	// use value (never nil)
}
```

These methods will first check the memory cache for data and if present, call completion immediately without dispatching to another thread. However if needed, they will asynchronously load data from storage on a background queue.

### Patterns

It can be a good idea for testing and flexibility to have your cache passed in on creation:

```swift
class Foo {
	let cache: PersistentCache<UUID, String>?
	
	init(cache: PersistentCache<UUID, String>? = PersistentCache(namespace: "Foo")) {
		self.cache = cache
	}
}

let fooA = Foo(cache: PersistentCache(storage: custom))
let fooA = Foo(cache: PersistentCache(storage: nil))
let fooB = Foo(cache: nil)
```

Notice that the cache is optional. If a test or a user of a framework wants to disable caching completely they can pass nil for the cache. Or to disable persistent storage and only use in memory caching, they can pass in a cache with no backing storage. And finally, if they want to use a custom storage method, they can pass in a cache with their specific storage class.