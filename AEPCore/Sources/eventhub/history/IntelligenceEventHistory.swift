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

/// Public API for accessing intelligence event history with rich metadata and aggregations
@objc(AEPIntelligenceEventHistory)
public class IntelligenceEventHistory: NSObject {
    
    private static let LOG_TAG = "IntelligenceEventHistory"
    private let database: IntelligenceEventHistoryDatabase
    private let queue: DispatchQueue
    
    init(database: IntelligenceEventHistoryDatabase) {
        self.database = database
        self.queue = DispatchQueue(label: "com.adobe.aep.intelligenceeventhistory", qos: .utility)
        super.init()
    }
    
    // MARK: - Callback-based API
    
    /// Records an intelligence event to the history database
    /// - Parameters:
    ///   - record: The intelligence event record to store
    ///   - completion: Callback with success status
    public func recordEvent(_ record: IntelligenceEventRecord, completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            let success = self.database.insert(record: record)
            if success {
                Log.debug(label: Self.LOG_TAG, "Recorded intelligence event: \(record.eventId)")
            } else {
                Log.error(label: Self.LOG_TAG, "Failed to record intelligence event: \(record.eventId)")
            }
            
            completion(success)
        }
    }
    
    /// Queries intelligence events matching the given criteria
    /// - Parameters:
    ///   - relevance: Optional relevance filter
    ///   - category: Optional category filter
    ///   - startTime: Optional start timestamp (milliseconds since epoch)
    ///   - endTime: Optional end timestamp (milliseconds since epoch)
    ///   - limit: Maximum number of records to return
    ///   - completion: Callback with array of intelligence event records
    public func queryEvents(
        relevance: IntelligenceRelevance? = nil,
        category: String? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int = 100,
        completion: @escaping ([IntelligenceEventRecord]) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            let records = self.database.select(
                relevance: relevance,
                category: category,
                startTime: startTime,
                endTime: endTime,
                limit: limit
            )
            
            Log.debug(label: Self.LOG_TAG, "Queried \(records.count) intelligence events")
            completion(records)
        }
    }
    
    /// Gets aggregated intelligence data by category
    /// - Parameters:
    ///   - startTime: Optional start timestamp (milliseconds since epoch)
    ///   - endTime: Optional end timestamp (milliseconds since epoch)
    ///   - completion: Callback with array of intelligence aggregates
    public func getAggregatesByCategory(
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        completion: @escaping ([IntelligenceAggregate]) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            let aggregates = self.database.aggregateByCategory(startTime: startTime, endTime: endTime)
            
            Log.debug(label: Self.LOG_TAG, "Retrieved \(aggregates.count) category aggregates")
            completion(aggregates)
        }
    }
    
    /// Gets time series data for trend analysis
    /// - Parameters:
    ///   - identifier: Category or item identifier
    ///   - bucketSizeMs: Time bucket size in milliseconds (e.g., 3600000 for 1 hour)
    ///   - startTime: Optional start timestamp
    ///   - endTime: Optional end timestamp
    ///   - completion: Callback with array of time series data points
    public func getTimeSeries(
        identifier: String,
        bucketSizeMs: Int64,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        completion: @escaping ([TimeSeriesDataPoint]) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            
            let dataPoints = self.database.queryTimeSeries(
                identifier: identifier,
                bucketSizeMs: bucketSizeMs,
                startTime: startTime,
                endTime: endTime
            )
            
            Log.debug(label: Self.LOG_TAG, "Retrieved \(dataPoints.count) time series data points")
            completion(dataPoints)
        }
    }
    
    /// Gets profile warmup data for initializing personalization
    /// - Parameters:
    ///   - recentEventLimit: Number of recent events to include
    ///   - completion: Callback with profile warmup data
    public func getProfileWarmupData(
        recentEventLimit: Int = 50,
        completion: @escaping (ProfileWarmupData?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            
            // Get category aggregates
            let aggregates = self.database.aggregateByCategory()
            
            // Get recent events
            let recentEvents = self.database.select(limit: recentEventLimit)
            
            guard !recentEvents.isEmpty else {
                Log.debug(label: Self.LOG_TAG, "No intelligence events found for profile warmup")
                completion(nil)
                return
            }
            
            // Calculate time range
            let timestamps = recentEvents.map { $0.timestamp }
            let oldest = timestamps.min() ?? 0
            let newest = timestamps.max() ?? 0
            
            let warmupData = ProfileWarmupData(
                categoryAggregates: aggregates,
                recentEvents: recentEvents,
                totalEventCount: recentEvents.count,
                timeRange: (oldest, newest)
            )
            
            Log.debug(label: Self.LOG_TAG, "Profile warmup data: \(aggregates.count) categories, \(recentEvents.count) events")
            completion(warmupData)
        }
    }
    
    /// Deletes intelligence events older than the specified number of days
    /// - Parameters:
    ///   - days: Number of days to retain
    ///   - completion: Callback with number of records deleted
    public func deleteOlderThan(days: Int, completion: @escaping (Int) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(0)
                return
            }
            
            let cutoffTimestamp = Int64(Date().timeIntervalSince1970 * 1000) - Int64(days * 24 * 60 * 60 * 1000)
            let deletedCount = self.database.deleteOlderThan(timestamp: cutoffTimestamp)
            
            Log.debug(label: Self.LOG_TAG, "Deleted \(deletedCount) events older than \(days) days")
            completion(deletedCount)
        }
    }
    
    /// Deletes all intelligence events
    /// - Parameter completion: Callback with success status
    public func deleteAll(completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            let success = self.database.deleteAll()
            if success {
                Log.debug(label: Self.LOG_TAG, "Deleted all intelligence events")
            } else {
                Log.error(label: Self.LOG_TAG, "Failed to delete all intelligence events")
            }
            
            completion(success)
        }
    }
    
    // MARK: - Async/Await API (iOS 13+)
    
    /// Records an intelligence event to the history database (async)
    /// - Parameter record: The intelligence event record to store
    /// - Returns: Success status
    @available(iOS 13.0, *)
    public func recordEvent(_ record: IntelligenceEventRecord) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            recordEvent(record) { success in
                continuation.resume(returning: success)
            }
        }
    }
    
    /// Queries intelligence events matching the given criteria (async)
    /// - Parameters:
    ///   - relevance: Optional relevance filter
    ///   - category: Optional category filter
    ///   - startTime: Optional start timestamp (milliseconds since epoch)
    ///   - endTime: Optional end timestamp (milliseconds since epoch)
    ///   - limit: Maximum number of records to return
    /// - Returns: Array of intelligence event records
    @available(iOS 13.0, *)
    public func queryEvents(
        relevance: IntelligenceRelevance? = nil,
        category: String? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int = 100
    ) async -> [IntelligenceEventRecord] {
        return await withCheckedContinuation { continuation in
            queryEvents(relevance: relevance, category: category, startTime: startTime, endTime: endTime, limit: limit) { records in
                continuation.resume(returning: records)
            }
        }
    }
    
    /// Gets aggregated intelligence data by category (async)
    /// - Parameters:
    ///   - startTime: Optional start timestamp (milliseconds since epoch)
    ///   - endTime: Optional end timestamp (milliseconds since epoch)
    /// - Returns: Array of intelligence aggregates
    @available(iOS 13.0, *)
    public func getAggregatesByCategory(
        startTime: Int64? = nil,
        endTime: Int64? = nil
    ) async -> [IntelligenceAggregate] {
        return await withCheckedContinuation { continuation in
            getAggregatesByCategory(startTime: startTime, endTime: endTime) { aggregates in
                continuation.resume(returning: aggregates)
            }
        }
    }
    
    /// Gets time series data for trend analysis (async)
    /// - Parameters:
    ///   - identifier: Category or item identifier
    ///   - bucketSizeMs: Time bucket size in milliseconds (e.g., 3600000 for 1 hour)
    ///   - startTime: Optional start timestamp
    ///   - endTime: Optional end timestamp
    /// - Returns: Array of time series data points
    @available(iOS 13.0, *)
    public func getTimeSeries(
        identifier: String,
        bucketSizeMs: Int64,
        startTime: Int64? = nil,
        endTime: Int64? = nil
    ) async -> [TimeSeriesDataPoint] {
        return await withCheckedContinuation { continuation in
            getTimeSeries(identifier: identifier, bucketSizeMs: bucketSizeMs, startTime: startTime, endTime: endTime) { dataPoints in
                continuation.resume(returning: dataPoints)
            }
        }
    }
    
    /// Gets profile warmup data for initializing personalization (async)
    /// - Parameter recentEventLimit: Number of recent events to include
    /// - Returns: Profile warmup data, or nil if no events found
    @available(iOS 13.0, *)
    public func getProfileWarmupData(recentEventLimit: Int = 50) async -> ProfileWarmupData? {
        return await withCheckedContinuation { continuation in
            getProfileWarmupData(recentEventLimit: recentEventLimit) { warmupData in
                continuation.resume(returning: warmupData)
            }
        }
    }
    
    /// Deletes intelligence events older than the specified number of days (async)
    /// - Parameter days: Number of days to retain
    /// - Returns: Number of records deleted
    @available(iOS 13.0, *)
    public func deleteOlderThan(days: Int) async -> Int {
        return await withCheckedContinuation { continuation in
            deleteOlderThan(days: days) { count in
                continuation.resume(returning: count)
            }
        }
    }
    
    /// Deletes all intelligence events (async)
    /// - Returns: Success status
    @available(iOS 13.0, *)
    public func deleteAll() async -> Bool {
        return await withCheckedContinuation { continuation in
            deleteAll { success in
                continuation.resume(returning: success)
            }
        }
    }
}
