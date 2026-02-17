/*
 Copyright 2024 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import AEPServices
import Foundation

/// Database operations for storing intelligence-relevant events with rich metadata
class IntelligenceEventHistoryDatabase {
    
    private static let LOG_TAG = "IntelligenceEventHistoryDatabase"
    
    private let TABLE_NAME = "IntelligenceEvents"
    
    // Column names
    private let COLUMN_EVENT_ID = "eventId"
    private let COLUMN_EVENT_HASH = "eventHash"
    private let COLUMN_TIMESTAMP = "timestamp"
    private let COLUMN_EVENT_TYPE = "eventType"
    private let COLUMN_EVENT_SOURCE = "eventSource"
    private let COLUMN_EVENT_NAME = "eventName"
    private let COLUMN_RELEVANCE = "relevance"
    private let COLUMN_COMMERCE_ACTION = "commerceAction"
    private let COLUMN_CATEGORY = "category"
    private let COLUMN_ITEM_ID = "itemId"
    private let COLUMN_ITEM_NAME = "itemName"
    private let COLUMN_ITEM_PRICE = "itemPrice"
    private let COLUMN_WEIGHT = "weight"
    private let COLUMN_EVENT_DATA = "eventData"
    private let COLUMN_XDM_DATA = "xdmData"
    
    private let database: SQLiteWrapper
    
    init(database: SQLiteWrapper) {
        self.database = database
        createTableIfNeeded()
    }
    
    // MARK: - Schema Management
    
    /// Creates the IntelligenceEvents table if it doesn't exist
    private func createTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS "\(TABLE_NAME)" (
            "\(COLUMN_EVENT_ID)"         TEXT PRIMARY KEY,
            "\(COLUMN_EVENT_HASH)"       INTEGER NOT NULL,
            "\(COLUMN_TIMESTAMP)"        INTEGER NOT NULL,
            "\(COLUMN_EVENT_TYPE)"       TEXT NOT NULL,
            "\(COLUMN_EVENT_SOURCE)"     TEXT NOT NULL,
            "\(COLUMN_EVENT_NAME)"       TEXT,
            "\(COLUMN_RELEVANCE)"        TEXT,
            "\(COLUMN_COMMERCE_ACTION)"  TEXT,
            "\(COLUMN_CATEGORY)"         TEXT,
            "\(COLUMN_ITEM_ID)"          TEXT,
            "\(COLUMN_ITEM_NAME)"        TEXT,
            "\(COLUMN_ITEM_PRICE)"       REAL,
            "\(COLUMN_WEIGHT)"           REAL,
            "\(COLUMN_EVENT_DATA)"       TEXT,
            "\(COLUMN_XDM_DATA)"         TEXT
        );
        
        CREATE INDEX IF NOT EXISTS "idx_intelligence_timestamp" ON "\(TABLE_NAME)" ("\(COLUMN_TIMESTAMP)");
        CREATE INDEX IF NOT EXISTS "idx_intelligence_category" ON "\(TABLE_NAME)" ("\(COLUMN_CATEGORY)");
        CREATE INDEX IF NOT EXISTS "idx_intelligence_relevance" ON "\(TABLE_NAME)" ("\(COLUMN_RELEVANCE)");
        """
        
        guard database.execute(sql: sql) else {
            Log.error(label: Self.LOG_TAG, "Failed to create IntelligenceEvents table")
            return
        }
        
        Log.debug(label: Self.LOG_TAG, "IntelligenceEvents table created successfully")
    }
    
    // MARK: - Insert Operations
    
    /// Inserts an intelligence event record into the database
    /// - Parameter record: The intelligence event record to insert
    /// - Returns: True if insertion was successful, false otherwise
    func insert(record: IntelligenceEventRecord) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO "\(TABLE_NAME)" (
            "\(COLUMN_EVENT_ID)", "\(COLUMN_EVENT_HASH)", "\(COLUMN_TIMESTAMP)",
            "\(COLUMN_EVENT_TYPE)", "\(COLUMN_EVENT_SOURCE)", "\(COLUMN_EVENT_NAME)",
            "\(COLUMN_RELEVANCE)", "\(COLUMN_COMMERCE_ACTION)", "\(COLUMN_CATEGORY)",
            "\(COLUMN_ITEM_ID)", "\(COLUMN_ITEM_NAME)", "\(COLUMN_ITEM_PRICE)",
            "\(COLUMN_WEIGHT)", "\(COLUMN_EVENT_DATA)", "\(COLUMN_XDM_DATA)"
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        let parameters: [Any?] = [
            record.eventId,
            record.eventHash,
            record.timestamp,
            record.eventType,
            record.eventSource,
            record.eventName,
            record.relevance.stringValue,
            record.commerceAction,
            record.category,
            record.itemId,
            record.itemName,
            record.itemPrice,
            record.weight,
            record.eventData,
            record.xdmData
        ]
        
        return database.execute(sql: sql, arguments: parameters)
    }
    
    // MARK: - Select Operations
    
    /// Selects intelligence events matching the given criteria
    /// - Parameters:
    ///   - relevance: Optional relevance filter
    ///   - category: Optional category filter
    ///   - startTime: Optional start timestamp (milliseconds since epoch)
    ///   - endTime: Optional end timestamp (milliseconds since epoch)
    ///   - limit: Maximum number of records to return
    /// - Returns: Array of intelligence event records
    func select(
        relevance: IntelligenceRelevance? = nil,
        category: String? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int = 100
    ) -> [IntelligenceEventRecord] {
        var sql = "SELECT * FROM \"\(TABLE_NAME)\" WHERE 1=1"
        var parameters: [Any?] = []
        
        if let relevance = relevance {
            sql += " AND \"\(COLUMN_RELEVANCE)\" = ?"
            parameters.append(relevance.stringValue)
        }
        
        if let category = category {
            sql += " AND \"\(COLUMN_CATEGORY)\" = ?"
            parameters.append(category)
        }
        
        if let startTime = startTime {
            sql += " AND \"\(COLUMN_TIMESTAMP)\" >= ?"
            parameters.append(startTime)
        }
        
        if let endTime = endTime {
            sql += " AND \"\(COLUMN_TIMESTAMP)\" <= ?"
            parameters.append(endTime)
        }
        
        sql += " ORDER BY \"\(COLUMN_TIMESTAMP)\" DESC LIMIT ?;"
        parameters.append(limit)
        
        var records: [IntelligenceEventRecord] = []
        
        guard database.query(sql: sql, arguments: parameters, rowHandler: { cursor in
            if let record = parseEventRecord(from: cursor) {
                records.append(record)
            }
            return true
        }) else {
            Log.error(label: Self.LOG_TAG, "Failed to query intelligence events")
            return []
        }
        
        return records
    }
    
    /// Aggregates intelligence events by category
    /// - Parameters:
    ///   - startTime: Optional start timestamp (milliseconds since epoch)
    ///   - endTime: Optional end timestamp (milliseconds since epoch)
    /// - Returns: Array of intelligence aggregates by category
    func aggregateByCategory(startTime: Int64? = nil, endTime: Int64? = nil) -> [IntelligenceAggregate] {
        var sql = """
        SELECT
            \"\(COLUMN_CATEGORY)\",
            COUNT(*) as eventCount,
            SUM(\"\(COLUMN_WEIGHT)\") as totalWeight,
            MAX(\"\(COLUMN_TIMESTAMP)\") as lastEventTimestamp,
            \"\(COLUMN_COMMERCE_ACTION)\",
            COUNT(\"\(COLUMN_COMMERCE_ACTION)\") as actionCount
        FROM \"\(TABLE_NAME)\"
        WHERE \"\(COLUMN_CATEGORY)\" IS NOT NULL
        """
        
        var parameters: [Any?] = []
        
        if let startTime = startTime {
            sql += " AND \"\(COLUMN_TIMESTAMP)\" >= ?"
            parameters.append(startTime)
        }
        
        if let endTime = endTime {
            sql += " AND \"\(COLUMN_TIMESTAMP)\" <= ?"
            parameters.append(endTime)
        }
        
        sql += " GROUP BY \"\(COLUMN_CATEGORY)\", \"\(COLUMN_COMMERCE_ACTION)\";"
        
        // First collect raw data grouped by category and action
        var categoryData: [String: (count: Int, weight: Double, timestamp: Int64, actions: [String: Int])] = [:]
        
        guard database.query(sql: sql, arguments: parameters, rowHandler: { cursor in
            guard let category = cursor["category"] as? String,
                  let eventCount = cursor["eventCount"] as? Int64,
                  let totalWeight = cursor["totalWeight"] as? Double,
                  let lastEventTimestamp = cursor["lastEventTimestamp"] as? Int64 else {
                return true
            }
            
            let action = cursor["commerceAction"] as? String
            let actionCount = cursor["actionCount"] as? Int64 ?? 0
            
            if var existing = categoryData[category] {
                existing.count += Int(eventCount)
                existing.weight += totalWeight
                existing.timestamp = max(existing.timestamp, lastEventTimestamp)
                if let action = action {
                    existing.actions[action] = (existing.actions[action] ?? 0) + Int(actionCount)
                }
                categoryData[category] = existing
            } else {
                var actions: [String: Int] = [:]
                if let action = action {
                    actions[action] = Int(actionCount)
                }
                categoryData[category] = (Int(eventCount), totalWeight, lastEventTimestamp, actions)
            }
            
            return true
        }) else {
            Log.error(label: Self.LOG_TAG, "Failed to aggregate intelligence events by category")
            return []
        }
        
        // Convert to IntelligenceAggregate objects
        return categoryData.map { category, data in
            IntelligenceAggregate(
                category: category,
                eventCount: data.count,
                totalWeight: data.weight,
                lastEventTimestamp: data.timestamp,
                actionCounts: data.actions
            )
        }.sorted { $0.totalWeight > $1.totalWeight }
    }
    
    /// Queries time series data for trend analysis
    /// - Parameters:
    ///   - identifier: Category or item identifier
    ///   - bucketSizeMs: Time bucket size in milliseconds (e.g., 3600000 for 1 hour)
    ///   - startTime: Optional start timestamp
    ///   - endTime: Optional end timestamp
    /// - Returns: Array of time series data points
    func queryTimeSeries(
        identifier: String,
        bucketSizeMs: Int64,
        startTime: Int64? = nil,
        endTime: Int64? = nil
    ) -> [TimeSeriesDataPoint] {
        var sql = """
        SELECT
            (\"\(COLUMN_TIMESTAMP)\" / ?) * ? as bucket,
            COUNT(*) as count,
            SUM(\"\(COLUMN_WEIGHT)\") as weight
        FROM \"\(TABLE_NAME)\"
        WHERE \"\(COLUMN_CATEGORY)\" = ? OR \"\(COLUMN_ITEM_ID)\" = ?
        """
        
        var parameters: [Any?] = [bucketSizeMs, bucketSizeMs, identifier, identifier]
        
        if let startTime = startTime {
            sql += " AND \"\(COLUMN_TIMESTAMP)\" >= ?"
            parameters.append(startTime)
        }
        
        if let endTime = endTime {
            sql += " AND \"\(COLUMN_TIMESTAMP)\" <= ?"
            parameters.append(endTime)
        }
        
        sql += " GROUP BY bucket ORDER BY bucket ASC;"
        
        var dataPoints: [TimeSeriesDataPoint] = []
        
        guard database.query(sql: sql, arguments: parameters, rowHandler: { cursor in
            guard let bucket = cursor["bucket"] as? Int64,
                  let count = cursor["count"] as? Int64,
                  let weight = cursor["weight"] as? Double else {
                return true
            }
            
            dataPoints.append(TimeSeriesDataPoint(
                timestamp: bucket,
                identifier: identifier,
                count: Int(count),
                weight: weight
            ))
            
            return true
        }) else {
            Log.error(label: Self.LOG_TAG, "Failed to query time series data")
            return []
        }
        
        return dataPoints
    }
    
    // MARK: - Delete Operations
    
    /// Deletes intelligence events older than the specified timestamp
    /// - Parameter timestamp: Timestamp threshold (milliseconds since epoch)
    /// - Returns: Number of records deleted
    func deleteOlderThan(timestamp: Int64) -> Int {
        let sql = "DELETE FROM \"\(TABLE_NAME)\" WHERE \"\(COLUMN_TIMESTAMP)\" < ?;"
        
        guard database.execute(sql: sql, arguments: [timestamp]) else {
            Log.error(label: Self.LOG_TAG, "Failed to delete old intelligence events")
            return 0
        }
        
        // Get number of deleted rows
        let countSql = "SELECT changes() as deleted;"
        var deletedCount = 0
        
        database.query(sql: countSql, arguments: [], rowHandler: { cursor in
            deletedCount = cursor["deleted"] as? Int ?? 0
            return true
        })
        
        Log.debug(label: Self.LOG_TAG, "Deleted \(deletedCount) old intelligence events")
        return deletedCount
    }
    
    /// Deletes all intelligence events
    /// - Returns: True if deletion was successful
    func deleteAll() -> Bool {
        let sql = "DELETE FROM \"\(TABLE_NAME)\";"
        return database.execute(sql: sql)
    }
    
    // MARK: - Helper Methods
    
    /// Parses an intelligence event record from a database cursor
    private func parseEventRecord(from cursor: [String: Any?]) -> IntelligenceEventRecord? {
        guard let eventId = cursor[COLUMN_EVENT_ID] as? String,
              let eventHash = cursor[COLUMN_EVENT_HASH] as? Int64,
              let timestamp = cursor[COLUMN_TIMESTAMP] as? Int64,
              let eventType = cursor[COLUMN_EVENT_TYPE] as? String,
              let eventSource = cursor[COLUMN_EVENT_SOURCE] as? String,
              let relevanceString = cursor[COLUMN_RELEVANCE] as? String,
              let relevance = IntelligenceRelevance(stringValue: relevanceString) else {
            return nil
        }
        
        return IntelligenceEventRecord(
            eventId: eventId,
            eventHash: Int(eventHash),
            timestamp: timestamp,
            eventType: eventType,
            eventSource: eventSource,
            eventName: cursor[COLUMN_EVENT_NAME] as? String,
            relevance: relevance,
            commerceAction: cursor[COLUMN_COMMERCE_ACTION] as? String,
            category: cursor[COLUMN_CATEGORY] as? String,
            itemId: cursor[COLUMN_ITEM_ID] as? String,
            itemName: cursor[COLUMN_ITEM_NAME] as? String,
            itemPrice: cursor[COLUMN_ITEM_PRICE] as? Double,
            weight: cursor[COLUMN_WEIGHT] as? Double ?? 1.0,
            eventData: cursor[COLUMN_EVENT_DATA] as? String,
            xdmData: cursor[COLUMN_XDM_DATA] as? String
        )
    }
}
