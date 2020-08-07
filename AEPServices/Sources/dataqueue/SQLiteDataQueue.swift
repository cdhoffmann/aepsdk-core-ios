/*
 Copyright 2020 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import Foundation

/// An implementation of protocol `DataQueue`
///    - implements a FIFO container (queue) for `DataEntity` objects
///    - `DataEntity` objects inside this queue will be persisted in SQLite database automatically
///    - the database operations is performed in series
class SQLiteDataQueue: DataQueue {
    public let databaseName: String
    public let databaseFilePath: FileManager.SearchPathDirectory
    public static let TABLE_NAME: String = "TB_AEP_DATA_ENTITY"
    
    private let serialQueue: DispatchQueue
    private let TB_KEY_UNIQUE_IDENTIFIER = "uniqueIdentifier"
    private let TB_KEY_TIMESTAMP = "timestamp"
    private let TB_KEY_DATA = "data"
    
    private let LOG_PREFIX = "SQLiteDataQueue"
    
    /// Creates a  new `DataQueue` with a database file path and a serial dispatch queue
    /// If it fails to create database or table, a `nil` will be returned.
    /// - Parameters:
    ///   - databaseName: the database name used to create SQLite database
    ///   - databaseFilePath: the SQLite database file will be stored in this directory, the default value is `.cachesDirectory`
    ///   - serialQueue: a serial dispatch queue used to perform database operations
    init?(databaseName: String, databaseFilePath: FileManager.SearchPathDirectory = .cachesDirectory, serialQueue: DispatchQueue) {
        self.databaseName = databaseName
        self.databaseFilePath = databaseFilePath
        self.serialQueue = serialQueue
        guard createTableIfNotExists(tableName: SQLiteDataQueue.TABLE_NAME) else {
            Log.warning(label: LOG_PREFIX, "Failed to initialize SQLiteDataQueue with database name '\(databaseName)'.")
            return nil
        }
    }
    
    func add(dataEntity: DataEntity) -> Bool {
        return serialQueue.sync {
            var dataString = ""
            if let data = dataEntity.data {
                dataString = String(data: data, encoding: .utf8) ?? ""
            }
            
            let insertRowStatement = """
            INSERT INTO \(SQLiteDataQueue.TABLE_NAME) (uniqueIdentifier, timestamp, data)
            VALUES ("\(dataEntity.uniqueIdentifier)", \(dataEntity.timestamp.millisecondsSince1970), '\(dataString)');
            """
            
            guard let connection = connect() else {
                return false
            }
            
            defer {
                disconnect(database: connection)
            }
            
            let result = SQLiteWrapper.execute(database: connection, sql: insertRowStatement)
            return result
        }
    }
    
    func peek() -> DataEntity? {
        return serialQueue.sync {
            let queryRowStatement = """
            SELECT min(id),uniqueIdentifier,timestamp,data FROM \(SQLiteDataQueue.TABLE_NAME);
            """
            guard let connection = connect() else {
                return nil
            }
            defer {
                disconnect(database: connection)
            }
            guard let result = SQLiteWrapper.query(database: connection, sql: queryRowStatement), let firstRow = result.first else {
                Log.trace(label: LOG_PREFIX, "Query returned no records: \(queryRowStatement).")
                return nil
            }
            
            guard let uniqueIdentifier = firstRow[TB_KEY_UNIQUE_IDENTIFIER], let dateString = firstRow[TB_KEY_TIMESTAMP], let dataString = firstRow[TB_KEY_DATA] else {
                Log.trace(label: LOG_PREFIX, "Database record did not have valid data: \(queryRowStatement).")
                return nil
            }
            guard let dateInt64 = Int64(dateString) else {
                Log.trace(label: LOG_PREFIX, "Database record had an invalid dateString: \(dateString).")
                return nil
            }
            let date = Date(milliseconds: dateInt64)
            guard !dataString.isEmpty else {
                return DataEntity(uniqueIdentifier: uniqueIdentifier, timestamp: date, data: nil)
            }
            let data = dataString.data(using: .utf8)
            return DataEntity(uniqueIdentifier: uniqueIdentifier, timestamp: date, data: data)
        }
    }
    
    func remove() -> Bool {
        return serialQueue.sync {
            guard let connection = connect() else {
                return false
            }
            defer {
                disconnect(database: connection)
            }
            let deleteRowStatement = """
            DELETE FROM \(SQLiteDataQueue.TABLE_NAME) order by id limit 1;
            """
            guard SQLiteWrapper.execute(database: connection, sql: deleteRowStatement) else {
                Log.warning(label: LOG_PREFIX, "Failed to delete oldest record from database: \(self.databaseName).")
                return false
            }
            return true
        }
    }
    
    func clear() -> Bool {
        return serialQueue.sync {
            let dropTableStatement = """
            DROP TABLE IF EXISTS \(SQLiteDataQueue.TABLE_NAME);
            """
            guard let connection = connect() else {
                return false
            }
            defer {
                disconnect(database: connection)
            }
            guard SQLiteWrapper.execute(database: connection, sql: dropTableStatement) else {
                Log.warning(label: LOG_PREFIX, "Failed to drop table '\(SQLiteDataQueue.TABLE_NAME)' in database: \(self.databaseName).")
                return false
            }
            
            return true
        }
    }
    
    func count() -> Int {
        return serialQueue.sync {
            let queryRowStatement = """
            SELECT count(id) FROM \(SQLiteDataQueue.TABLE_NAME);
            """
            guard let connection = connect() else {
                return 0
            }
            defer {
                disconnect(database: connection)
            }
            guard let result = SQLiteWrapper.query(database: connection, sql: queryRowStatement), let countAsString = result.first?.first?.value else {
                Log.trace(label: LOG_PREFIX, "Query returned no records: \(queryRowStatement).")
                return 0
            }
                        
            return Int(countAsString) ?? 0            
        }
    }
    
    private func connect() -> OpaquePointer? {
        if let database = SQLiteWrapper.connect(databaseFilePath: databaseFilePath, databaseName: databaseName) {
            return database
        } else {
            Log.warning(label: LOG_PREFIX, "Failed to connect to database: \(databaseName).")
            return nil
        }
    }
    
    private func disconnect(database: OpaquePointer) {
        SQLiteWrapper.disconnect(database: database)
    }
    
    private func createTableIfNotExists(tableName: String) -> Bool {
        guard let connection = connect() else {
            return false
        }
        defer {
            disconnect(database: connection)
        }
        if SQLiteWrapper.tableExists(database: connection, tableName: SQLiteDataQueue.TABLE_NAME) {
            return true
        } else {
            let createTableStatement = """
            CREATE TABLE "\(tableName)" (
                "id"          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
                "uniqueIdentifier"        TEXT NOT NULL UNIQUE,
                "timestamp"   INTEGER NOT NULL,
                "data"        TEXT
            );
            """
            
            let result = SQLiteWrapper.execute(database: connection, sql: createTableStatement)
            if result {
                Log.trace(label: LOG_PREFIX, "Successfully created table '\(tableName)'.")
            } else {
                Log.warning(label: LOG_PREFIX, "Failed to create table '\(tableName)'.")
            }
            
            return result
        }
    }
}

extension Date {
    var millisecondsSince1970: Int64 {
        return Int64((timeIntervalSince1970 * 1000.0).rounded())
    }
    
    init(milliseconds: Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}
