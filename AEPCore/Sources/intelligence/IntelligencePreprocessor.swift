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

/// Preprocessor that classifies events for intelligence and tags them with metadata
class IntelligencePreprocessor {
    
    private static let LOG_TAG = "IntelligencePreprocessor"
    
    /// Configuration for the intelligence preprocessor
    struct Config {
        var enabled: Bool = false
        var domain: String? = nil
        var customEventTypes: [String] = []
        var provider: String = "FoundationModels"
    }
    
    /// Metadata extracted from an event for intelligence purposes
    struct EventMetadata {
        let relevance: IntelligenceRelevance
        let commerceAction: String?
        let category: String?
        let itemId: String?
        let itemName: String?
        let itemPrice: Double?
        let weight: Double
    }
    
    private var config: Config = Config()
    private let queue = DispatchQueue(label: "com.adobe.aep.intelligencepreprocessor", qos: .utility)
    private var intelligenceHistory: IntelligenceEventHistory?
    
    init() {
        // Intelligence history will be initialized when EventHistoryProvider is available
    }
    
    /// Sets the intelligence event history instance
    /// - Parameter history: The intelligence event history instance
    func setIntelligenceHistory(_ history: IntelligenceEventHistory) {
        queue.async { [weak self] in
            self?.intelligenceHistory = history
        }
    }
    
    /// Updates the preprocessor configuration
    /// - Parameter configuration: Dictionary containing intelligence configuration
    func updateConfiguration(_ configuration: [String: Any]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let enabled = configuration[IntelligenceConstants.ConfigKeys.ENABLED] as? Bool ?? false
            let domain = configuration[IntelligenceConstants.ConfigKeys.DOMAIN] as? String
            let eventTypes = configuration[IntelligenceConstants.ConfigKeys.EVENT_TYPES] as? [String] ?? []
            let provider = configuration[IntelligenceConstants.ConfigKeys.PROVIDER] as? String ?? "FoundationModels"
            
            self.config = Config(
                enabled: enabled,
                domain: domain,
                customEventTypes: eventTypes,
                provider: provider
            )
            
            Log.debug(label: Self.LOG_TAG, "Intelligence preprocessor updated - enabled: \(enabled), domain: \(domain ?? "none"), custom types: \(eventTypes.count)")
        }
    }
    
    /// Processes an event through the intelligence preprocessor
    /// - Parameter event: The event to process
    /// - Returns: The event, potentially modified with intelligence metadata
    func process(_ event: Event) -> Event {
        // Quick check if intelligence is enabled (avoid queue if disabled)
        guard config.enabled else {
            return event
        }
        
        // Classify the event
        guard let metadata = classifyEvent(event) else {
            return event
        }
        
        // Tag event with intelligence metadata for real-time processing
        var modifiedData = event.data ?? [:]
        modifiedData[IntelligenceConstants.EventDataKeys.RELEVANCE] = metadata.relevance.stringValue
        
        if let commerceAction = metadata.commerceAction {
            modifiedData[IntelligenceConstants.EventDataKeys.COMMERCE_ACTION] = commerceAction
        }
        if let category = metadata.category {
            modifiedData[IntelligenceConstants.EventDataKeys.CATEGORY] = category
        }
        if let itemId = metadata.itemId {
            modifiedData[IntelligenceConstants.EventDataKeys.ITEM_ID] = itemId
        }
        if let itemName = metadata.itemName {
            modifiedData[IntelligenceConstants.EventDataKeys.ITEM_NAME] = itemName
        }
        if let itemPrice = metadata.itemPrice {
            modifiedData[IntelligenceConstants.EventDataKeys.ITEM_PRICE] = itemPrice
        }
        modifiedData[IntelligenceConstants.EventDataKeys.WEIGHT] = metadata.weight
        
        // Persist to IntelligenceEventHistory asynchronously
        persistToHistory(event: event, metadata: metadata, modifiedData: modifiedData)
        
        // Create mask for intelligence extension to listen for
        let mask = createMask(for: metadata)
        
        // Return modified event with intelligence tags
        return Event(
            name: event.name,
            type: event.type,
            source: event.source,
            data: modifiedData,
            mask: mask
        )
    }
    
    // MARK: - Event Classification
    
    /// Classifies an event and extracts intelligence metadata
    /// - Parameter event: The event to classify
    /// - Returns: Event metadata if the event is relevant, nil otherwise
    private func classifyEvent(_ event: Event) -> EventMetadata? {
        // Check for XDM commerce events
        if let xdm = event.data?["xdm"] as? [String: Any] {
            return classifyXDMCommerceEvent(xdm: xdm, event: event)
        }
        
        // Check for lifecycle events
        if event.type == EventType.lifecycle {
            return EventMetadata(
                relevance: .lifecycle,
                commerceAction: nil,
                category: "lifecycle",
                itemId: nil,
                itemName: event.name,
                itemPrice: nil,
                weight: IntelligenceConstants.EventWeights.LIFECYCLE
            )
        }
        
        // Check for custom configured event types
        if config.customEventTypes.contains(event.type) {
            return EventMetadata(
                relevance: .custom,
                commerceAction: nil,
                category: extractCategoryFromCustomEvent(event),
                itemId: nil,
                itemName: event.name,
                itemPrice: nil,
                weight: IntelligenceConstants.EventWeights.CUSTOM
            )
        }
        
        return nil
    }
    
    /// Classifies an XDM commerce event
    /// - Parameters:
    ///   - xdm: The XDM data dictionary
    ///   - event: The original event
    /// - Returns: Event metadata for commerce events
    private func classifyXDMCommerceEvent(xdm: [String: Any], event: Event) -> EventMetadata? {
        guard let commerce = xdm[IntelligenceConstants.XDM.COMMERCE] as? [String: Any] else {
            return nil
        }
        
        // Determine commerce action and weight
        var commerceAction: String?
        var weight: Double = 1.0
        
        if commerce[IntelligenceConstants.XDM.PRODUCT_VIEWS] != nil {
            commerceAction = IntelligenceConstants.CommerceAction.PRODUCT_VIEW
            weight = IntelligenceConstants.EventWeights.PRODUCT_VIEW
        } else if commerce[IntelligenceConstants.XDM.PRODUCT_LIST_ADDS] != nil {
            commerceAction = IntelligenceConstants.CommerceAction.ADD_TO_CART
            weight = IntelligenceConstants.EventWeights.ADD_TO_CART
        } else if commerce[IntelligenceConstants.XDM.PRODUCT_LIST_REMOVALS] != nil {
            commerceAction = IntelligenceConstants.CommerceAction.REMOVE_FROM_CART
            weight = IntelligenceConstants.EventWeights.REMOVE_FROM_CART
        } else if commerce[IntelligenceConstants.XDM.PURCHASES] != nil {
            commerceAction = IntelligenceConstants.CommerceAction.PURCHASE
            weight = IntelligenceConstants.EventWeights.PURCHASE
        } else {
            return nil // Not a commerce action we care about
        }
        
        // Extract product information from productListItems
        guard let productListItems = xdm[IntelligenceConstants.XDM.PRODUCT_LIST_ITEMS] as? [[String: Any]],
              let firstProduct = productListItems.first else {
            return nil
        }
        
        let itemId = firstProduct[IntelligenceConstants.XDM.SKU] as? String
        let itemName = firstProduct[IntelligenceConstants.XDM.NAME] as? String
        let itemPrice = firstProduct[IntelligenceConstants.XDM.PRICE_TOTAL] as? Double
        
        // Extract category
        var category: String?
        if let categories = firstProduct[IntelligenceConstants.XDM.PRODUCT_CATEGORIES] as? [[String: Any]],
           let firstCategory = categories.first,
           let categoryName = firstCategory["name"] as? String {
            category = categoryName
        } else if let categoryId = firstProduct["categoryId"] as? String {
            category = categoryId
        }
        
        return EventMetadata(
            relevance: .commerce,
            commerceAction: commerceAction,
            category: category,
            itemId: itemId,
            itemName: itemName,
            itemPrice: itemPrice,
            weight: weight
        )
    }
    
    /// Extracts category from a custom event
    /// - Parameter event: The event to extract category from
    /// - Returns: Category string if found
    private func extractCategoryFromCustomEvent(_ event: Event) -> String? {
        // Look for common category field names in event data
        if let data = event.data {
            if let category = data["category"] as? String {
                return category
            }
            if let type = data["type"] as? String {
                return type
            }
            if let action = data["action"] as? String {
                return action
            }
        }
        
        // Fall back to event type as category
        return event.type
    }
    
    // MARK: - Persistence
    
    /// Persists event to IntelligenceEventHistory asynchronously
    /// - Parameters:
    ///   - event: The original event
    ///   - metadata: The extracted metadata
    ///   - modifiedData: The modified event data with intelligence tags
    private func persistToHistory(event: Event, metadata: EventMetadata, modifiedData: [String: Any]) {
        queue.async { [weak self] in
            guard let self = self, let history = self.intelligenceHistory else {
                return
            }
            
            // Serialize event data and XDM to JSON
            let eventDataJSON = try? JSONSerialization.data(with: modifiedData, options: [])
            let eventDataString = eventDataJSON.flatMap { String(data: $0, encoding: .utf8) }
            
            var xdmDataString: String?
            if let xdm = event.data?["xdm"] as? [String: Any] {
                let xdmJSON = try? JSONSerialization.data(withJSONObject: xdm, options: [])
                xdmDataString = xdmJSON.flatMap { String(data: $0, encoding: .utf8) }
            }
            
            // Create intelligence event record
            let record = IntelligenceEventRecord(
                eventId: event.id.uuidString,
                eventHash: event.hashValue,
                timestamp: Int64(event.timestamp.timeIntervalSince1970 * 1000),
                eventType: event.type,
                eventSource: event.source,
                eventName: event.name,
                relevance: metadata.relevance,
                commerceAction: metadata.commerceAction,
                category: metadata.category,
                itemId: metadata.itemId,
                itemName: metadata.itemName,
                itemPrice: metadata.itemPrice,
                weight: metadata.weight,
                eventData: eventDataString,
                xdmData: xdmDataString
            )
            
            // Record to history database
            history.recordEvent(record) { success in
                if success {
                    Log.trace(label: Self.LOG_TAG, "Persisted intelligence event: \(event.id)")
                } else {
                    Log.warning(label: Self.LOG_TAG, "Failed to persist intelligence event: \(event.id)")
                }
            }
        }
    }
    
    // MARK: - Event Masking
    
    /// Creates an event mask for the intelligence extension to listen for
    /// - Parameter metadata: The event metadata
    /// - Returns: Array of EventType/EventSource masks
    private func createMask(for metadata: EventMetadata) -> [String]? {
        // Intelligence extension will listen for events with intelligence.relevance tag
        // No specific mask needed - extension can filter by checking for the tag
        return nil
    }
}
