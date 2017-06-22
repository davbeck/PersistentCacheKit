import Foundation
import CSQLiteMac


final class SQLiteDB {
	public enum Error: Swift.Error, LocalizedError {
		case sqlite(code: Int32, message: String?)
		case invalidDatabase
		case invalidStatement
		case invalidUTF8String
		
		
		public var errorDescription: String? {
			switch self {
			case .sqlite(code: let code, message: let message):
				if let message = message {
					return "SQLite error \(code): '\(message)'."
				} else {
					return "SQLite error \(code)."
				}
			case .invalidDatabase:
				return "Could not create database connection."
			case .invalidStatement:
				return "Could not create database statement."
			case .invalidUTF8String:
				return "Invalid UTF8 String"
			}
		}
	}
	
	public static let shared: SQLiteDB = {
		do {
			var url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			url.appendPathComponent("SQLiteDB.shared")
			url.appendPathComponent("storage.sqlite")
			let storage = try SQLiteDB(url: url)
			
			return storage
		} catch {
			fatalError("failed to create shared SQLiteDB: \(error)")
		}
	}()
	
	public let url: URL
	fileprivate let rawValue: OpaquePointer
	
	public init(url: URL) throws {
		self.url = url
		
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
		
		var db: OpaquePointer?
		let result = sqlite3_open(url.path, &db)
		guard result == SQLITE_OK || result == SQLITE_DONE else {
			throw Error.sqlite(code: result, message: String(utf8String: sqlite3_errmsg(db)))
		}
		guard let rawValue = db else {
			throw Error.invalidDatabase
		}
		
		self.rawValue = rawValue
		
		
		try self.createTable()
	}
	
	deinit {
		do {
			try close()
		} catch {
			print("error closing database: \(error)")
		}
	}
	
	func close() throws {
		let result = sqlite3_close(rawValue)
		guard result == SQLITE_OK || result == SQLITE_DONE else {
			throw Error.sqlite(code: result, message: self.errorMessage())
		}
	}
	
	func errorMessage() -> String? {
		return String(utf8String: sqlite3_errmsg(rawValue))
	}
	
	
	// MARK: - Queries
	
	private func createTable() throws {
		let statement = try self.preparedStatement(forSQL: "CREATE TABLE IF NOT EXISTS deploy (id TEXT PRIMARY KEY NOT NULL, repoName TEXT, branch TEXT, status TEXT, error TEXT, initiated INTEGER, started INTEGER, ended INTEGER, command TEXT, sha TEXT)", shouldCache: false)
		try statement.step()
	}
	
	
	// MARK: - SQLite
	
	fileprivate var preparedStatements = [String:SQLitePreparedStatement]()
	
	func preparedStatement(forSQL sql: String, shouldCache: Bool = true) throws -> SQLitePreparedStatement {
		if let statement = preparedStatements[sql] {
			return statement
		}
		
		let statement = try SQLitePreparedStatement(database: self, sql: sql)
		
		if shouldCache {
			preparedStatements[sql] = statement
		}
		
		return statement
	}
	
	func verify(result: Int32) throws {
		if result != SQLITE_DONE && result != SQLITE_ROW && result != SQLITE_OK {
			throw Error.sqlite(code: result, message: self.errorMessage())
		}
	}
}

final class SQLitePreparedStatement {
	weak var database: SQLiteDB?
	fileprivate let rawValue: OpaquePointer
	
	fileprivate init(rawValue: OpaquePointer) {
		self.rawValue = rawValue
	}
	
	init(database: SQLiteDB, sql: String) throws {
		self.database = database
		var statement: OpaquePointer? = nil
		
		let result = sqlite3_prepare_v2(database.rawValue, sql, -1, &statement, nil)
		guard result == SQLITE_OK || result == SQLITE_DONE else {
			throw SQLiteDB.Error.sqlite(code: result, message: database.errorMessage())
		}
		guard let rawValue = statement else {
			throw SQLiteDB.Error.invalidStatement
		}
		
		self.rawValue = rawValue
	}
	
	deinit {
		sqlite3_finalize(rawValue)
	}
	
	
	@discardableResult
	func step() throws -> Bool {
		let result = sqlite3_step(rawValue)
		
		guard result == SQLITE_DONE || result == SQLITE_ROW || result == SQLITE_OK else {
			throw SQLiteDB.Error.sqlite(code: result, message: database?.errorMessage())
		}
		
		return result == SQLITE_ROW
	}
	
	func reset() throws {
		let result = sqlite3_reset(rawValue)
		
		guard result == SQLITE_DONE || result == SQLITE_OK else {
			throw SQLiteDB.Error.sqlite(code: result, message: database?.errorMessage())
		}
		
		self.boundData = [:]
	}
	
	
	// MARK: - Binding
	
	func bindNull(at index: Int32) throws {
		try database?.verify(result: sqlite3_bind_null(rawValue, index))
	}
	
	func bind(_ value: Int?, at index: Int32) throws {
		guard let value = value else {
			try self.bindNull(at: index)
			return
		}
		
		if MemoryLayout<Int>.size == MemoryLayout<Int32>.size {
			try database?.verify(result: sqlite3_bind_int(rawValue, index, Int32(value)))
		} else {
			try database?.verify(result: sqlite3_bind_int64(rawValue, index, Int64(value)))
		}
	}
	
	func bind(_ value: Double?, at index: Int32) throws {
		guard let value = value else {
			try self.bindNull(at: index)
			return
		}
		
		try database?.verify(result: sqlite3_bind_double(rawValue, index, value))
	}
	
	func bind(_ value: String?, at index: Int32) throws {
		guard let value = value else {
			try self.bindNull(at: index)
			return
		}
		
		guard let data = value.data(using: .utf8) else { throw SQLiteDB.Error.invalidUTF8String }
		
		try data.withUnsafeBytes({ (bytes: UnsafePointer<Int8>) in
			try database?.verify(result: sqlite3_bind_text(rawValue, index, bytes, Int32(data.count), nil))
		})
	}
	
	/// Data bound as a blob
	///
	/// We need to keep this data alive until the blob is replaced at the given index or the receiver is deallocated.
	fileprivate var boundData = [Int32:Data]()
	
	func bind(_ value: Data?, at index: Int32) throws {
		guard let value = value else {
			try self.bindNull(at: index)
			return
		}
		
		boundData[index] = value
		
		_ = try value.withUnsafeBytes { (bytes) in
			try database?.verify(result: sqlite3_bind_blob(rawValue, index, bytes, Int32(value.count)) { _ in })
		}
	}
	
	func bind(_ value: Date?, at index: Int32) throws {
		try self.bind(value?.timeIntervalSince1970, at: index)
	}
	
	
	// MARK: - Query Results
	
	enum ColumnType {
		case integer
		case float
		case blob
		case null
		
		case text
		
		init?(sqliteRawValue: Int32) {
			switch sqliteRawValue {
			case SQLITE_INTEGER:
				self = .integer
			case SQLITE_FLOAT:
				self = .float
			case SQLITE_BLOB:
				self = .blob
			case SQLITE_NULL:
				self = .null
			case SQLITE_TEXT, SQLITE3_TEXT:
				self = .text
			default:
				return nil
			}
		}
	}
	
	func getType(atColumn column: Int32) -> ColumnType? {
		return ColumnType(sqliteRawValue: sqlite3_column_type(rawValue, column))
	}
	
	func getInt(atColumn column: Int32) -> Int? {
		guard self.getType(atColumn: column) != .null else { return nil }
		
		if MemoryLayout<Int>.size == MemoryLayout<Int32>.size {
			return Int(sqlite3_column_int(rawValue, column))
		} else {
			return Int(sqlite3_column_int64(rawValue, column))
		}
	}
	
	func getDouble(atColumn column: Int32) -> Double? {
		guard self.getType(atColumn: column) != .null else { return nil }
		
		return sqlite3_column_double(rawValue, column)
	}
	
	func getString(atColumn column: Int32) -> String? {
		guard self.getType(atColumn: column) != .null else { return nil }
		
		guard let cString = sqlite3_column_text(rawValue, column) else { return nil }
		return String(cString: cString)
	}
	
	func getData(atColumn column: Int32) -> Data? {
		guard self.getType(atColumn: column) != .null else { return nil }
		
		guard let bytes = sqlite3_column_blob(rawValue, column) else { return nil }
		let count = sqlite3_column_bytes(rawValue, column)
		
		return Data(bytes: bytes, count: Int(count))
	}
	
	func date(at column: Int32) -> Date? {
		guard let timeIntervalSince1970 = self.getDouble(atColumn: column) else { return nil }
		return Date(timeIntervalSince1970: timeIntervalSince1970)
	}
}
