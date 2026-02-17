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

import Foundation

/// Represents the relevance classification of an event for intelligence purposes
@objc(AEPIntelligenceRelevance)
public enum IntelligenceRelevance: Int, Codable {
    case none = 0
    case commerce = 1
    case lifecycle = 2
    case custom = 3
    
    var stringValue: String {
        switch self {
        case .none: return "none"
        case .commerce: return "commerce"
        case .lifecycle: return "lifecycle"
        case .custom: return "custom"
        }
    }
    
    init?(stringValue: String) {
        switch stringValue.lowercased() {
        case "commerce": self = .commerce
        case "lifecycle": self = .lifecycle
        case "custom": self = .custom
        case "none": self = .none
        default: return nil
        }
    }
}

/// A rich record of an intelligence-relevant event with full metadata
@objc(AEPIntelligenceEventRecord)
public class IntelligenceEventRecord: NSObject, Codable {
    /// Unique identifier for the event
    public let eventId: String
    
    /// Hash of the event for deduplication
    public let eventHash: Int
    
    /// Timestamp when the event occurred (milliseconds since epoch)
    public let timestamp: Int64
    
    /// Event type (e.g., "com.adobe.eventType.edge")
    public let eventType: String
    
    /// Event source (e.g., "com.adobe.eventSource.requestContent")
    public let eventSource: String
    
    /// Optional human-readable event name
    public let eventName: String?
    
    /// Relevance classification for intelligence
    public let relevance: IntelligenceRelevance
    
    /// Commerce action if this is a commerce event (e.g., "productView", "addToCart", "purchase")
    public let commerceAction: String?
    
    /// Category/product type for commerce events
    public let category: String?
    
    /// Item/product identifier
    public let itemId: String?
    
    /// Item/product name
    public let itemName: String?
    
    /// Item/product price
    public let itemPrice: Double?
    
    /// Weight/importance of this event for personalization
    public let weight: Double
    
    /// Full event data as JSON string
    public let eventData: String?
    
    /// XDM data as JSON string (for commerce events)
    public let xdmData: String?
    
    public init(
        eventId: String,
        eventHash: Int,
        timestamp: Int64,
        eventType: String,
        eventSource: String,
        eventName: String? = nil,
        relevance: IntelligenceRelevance,
        commerceAction: String? = nil,
        category: String? = nil,
        itemId: String? = nil,
        itemName: String? = nil,
        itemPrice: Double? = nil,
        weight: Double = 1.0,
        eventData: String? = nil,
        xdmData: String? = nil
    ) {
        self.eventId = eventId
        self.eventHash = eventHash
        self.timestamp = timestamp
        self.eventType = eventType
        self.eventSource = eventSource
        self.eventName = eventName
        self.relevance = relevance
        self.commerceAction = commerceAction
        self.category = category
        self.itemId = itemId
        self.itemName = itemName
        self.itemPrice = itemPrice
        self.weight = weight
        self.eventData = eventData
        self.xdmData = xdmData
        super.init()
    }
}

/// Aggregated intelligence data by category
@objc(AEPIntelligenceAggregate)
public class IntelligenceAggregate: NSObject, Codable {
    /// Category identifier
    public let category: String
    
    /// Total number of events in this category
    public let eventCount: Int
    
    /// Total weighted score for this category
    public let totalWeight: Double
    
    /// Most recent event timestamp (milliseconds since epoch)
    public let lastEventTimestamp: Int64
    
    /// Commerce actions distribution (action: count)
    public let actionCounts: [String: Int]
    
    public init(
        category: String,
        eventCount: Int,
        totalWeight: Double,
        lastEventTimestamp: Int64,
        actionCounts: [String: Int] = [:]
    ) {
        self.category = category
        self.eventCount = eventCount
        self.totalWeight = totalWeight
        self.lastEventTimestamp = lastEventTimestamp
        self.actionCounts = actionCounts
        super.init()
    }
}

/// Time series data point for trend analysis
@objc(AEPTimeSeriesDataPoint)
public class TimeSeriesDataPoint: NSObject, Codable {
    /// Time bucket (e.g., hour, day) as timestamp (milliseconds since epoch)
    public let timestamp: Int64
    
    /// Category or item identifier
    public let identifier: String
    
    /// Event count in this time bucket
    public let count: Int
    
    /// Total weighted score in this time bucket
    public let weight: Double
    
    public init(timestamp: Int64, identifier: String, count: Int, weight: Double) {
        self.timestamp = timestamp
        self.identifier = identifier
        self.count = count
        self.weight = weight
        super.init()
    }
}

/// Profile warmup data structure for initializing personalization profiles
@objc(AEPProfileWarmupData)
public class ProfileWarmupData: NSObject, Codable {
    /// Category-level aggregates
    public let categoryAggregates: [IntelligenceAggregate]
    
    /// Recent individual events (last N events)
    public let recentEvents: [IntelligenceEventRecord]
    
    /// Total event count
    public let totalEventCount: Int
    
    /// Time range covered (oldest to newest event)
    public let timeRange: (oldest: Int64, newest: Int64)
    
    public init(
        categoryAggregates: [IntelligenceAggregate],
        recentEvents: [IntelligenceEventRecord],
        totalEventCount: Int,
        timeRange: (oldest: Int64, newest: Int64)
    ) {
        self.categoryAggregates = categoryAggregates
        self.recentEvents = recentEvents
        self.totalEventCount = totalEventCount
        self.timeRange = timeRange
        super.init()
    }
    
    enum CodingKeys: String, CodingKey {
        case categoryAggregates
        case recentEvents
        case totalEventCount
        case oldestTimestamp
        case newestTimestamp
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryAggregates = try container.decode([IntelligenceAggregate].self, forKey: .categoryAggregates)
        recentEvents = try container.decode([IntelligenceEventRecord].self, forKey: .recentEvents)
        totalEventCount = try container.decode(Int.self, forKey: .totalEventCount)
        let oldest = try container.decode(Int64.self, forKey: .oldestTimestamp)
        let newest = try container.decode(Int64.self, forKey: .newestTimestamp)
        timeRange = (oldest, newest)
        super.init()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(categoryAggregates, forKey: .categoryAggregates)
        try container.encode(recentEvents, forKey: .recentEvents)
        try container.encode(totalEventCount, forKey: .totalEventCount)
        try container.encode(timeRange.oldest, forKey: .oldestTimestamp)
        try container.encode(timeRange.newest, forKey: .newestTimestamp)
    }
}
