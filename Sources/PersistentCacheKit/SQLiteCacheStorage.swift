import Foundation
import CSQLiteMac


public final class SQLiteCacheStorage: CacheStorage {
	public static let shared: SQLiteCacheStorage = {
		do {
			var url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			url.appendPathComponent("SQLiteCacheStorage.shared")
			url.appendPathComponent("storage.sqlite")
			let storage = try SQLiteCacheStorage(url: url)
			
			return storage
		} catch {
			fatalError("SQLiteCacheStorage - failed to create shared db: \(error)")
		}
	}()
	
	
	private let db: SQLiteDB
	private let queue = DispatchQueue(label: "SQLiteCacheStorage")
	
	public var url: URL {
		return db.url
	}
	
	public init(url: URL) throws {
		self.db = try SQLiteDB(url: url)
		
		try self.createTable()
	}
	
	public var maxFilesize: Int? {
		didSet {
			self.queue.async {
				do {
					try self._trimFilesize()
				} catch {
					print("SQLiteCacheStorage - failed to trim cache size: \(error)")
				}
			}
		}
	}
	
	
	// MARK: - Queries
	
	private func createTable() throws {
		let statement = try db.preparedStatement(forSQL: "CREATE TABLE IF NOT EXISTS cache_storage (key TEXT PRIMARY KEY NOT NULL, data BLOB, createdAt INTEGER)", shouldCache: false)
		try statement.step()
	}
	
	
	public subscript(key: String) -> Data? {
		get {
			return queue.sync {
				var data: Data?
				
				do {
					let sql = "SELECT data FROM cache_storage WHERE key = ?"
					let statement = try self.db.preparedStatement(forSQL: sql)
					
					try statement.bind(key, at: 1)
					
					if try statement.step() {
						data = statement.getData(atColumn: 0)
					}
					
					try statement.reset()
				} catch {
					print("SQLiteCacheStorage - error retrieving data from SQLite: \(error)")
				}
				
				return data
			}
		}
		set {
			queue.async {
				do {
					let sql = "INSERT OR REPLACE INTO cache_storage (key, data, createdAt) VALUES (?, ?, ?)"
					
					let statement = try self.db.preparedStatement(forSQL: sql)
					
					try statement.bind(key, at: 1)
					try statement.bind(newValue, at: 2)
					try statement.bind(Date(), at: 3)
					
					try statement.step()
					try statement.reset()
					
					try self.trimIfNeeded()
				} catch {
					print("SQLiteCacheStorage - error saving data to SQLite: \(error)")
				}
			}
		}
	}
	
	
	private var lastTrimmed: Date?
	
	private func currentFilesize(fast: Bool) throws -> Int {
		if fast {
			var currentFilesize = 0
			
			let sql = "SELECT SUM(LENGTH(data)) AS filesize FROM cache_storage;"
			let statement = try self.db.preparedStatement(forSQL: sql)
			
			if try statement.step() {
				currentFilesize = statement.getInt(atColumn: 0) ?? 0
			}
			
			try statement.reset()
			
			return currentFilesize
		} else {
			return try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
		}
	}
	
	private func objectCount() throws -> Int {
		var count = 0
		
		let sql = "SELECT COUNT(*) AS count FROM cache_storage;"
		let statement = try self.db.preparedStatement(forSQL: sql)
		
		if try statement.step() {
			count = statement.getInt(atColumn: 0) ?? 0
		}
		
		try statement.reset()
		
		return count
	}
	
	private func trimIfNeeded() throws {
		if let lastTrimmed = lastTrimmed, -lastTrimmed.timeIntervalSinceNow <= 60 {
			return
		}
		
		try _trimFilesize()
	}
	
	public func trimFilesize() throws {
		try queue.sync {
			try self._trimFilesize(fast: false)
		}
	}
	
	private func _trimFilesize(fast: Bool = false) throws {
		guard let maxFilesize = maxFilesize else { return }
		var currentFileSize = try currentFilesize(fast: fast)
		var iteration = 0
		
		while currentFileSize > maxFilesize && iteration < 5 {
			print("SQLiteCacheStorage - currentFilesize \(currentFileSize) is greater than maxFilesize \(maxFilesize). Trimming cache.")
			
			let count = try Int(ceil(Double(objectCount()) / 2))
			
			do {
				let sql = "DELETE FROM cache_storage WHERE key IN (SELECT key FROM cache_storage ORDER BY createdAt ASC LIMIT ?);"
				let statement = try self.db.preparedStatement(forSQL: sql)
				try statement.bind(count, at: 1)
				try statement.step()
				try statement.reset()
			}
			
			do {
				let sql = "VACUUM;"
				let statement = try self.db.preparedStatement(forSQL: sql)
				try statement.step()
				try statement.reset()
			}
			
			currentFileSize = try currentFilesize(fast: false)
			iteration += 1
		}
		
		lastTrimmed = Date()
	}
}
