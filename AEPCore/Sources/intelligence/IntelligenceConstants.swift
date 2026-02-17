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

/// Constants for the Intelligence preprocessor layer
enum IntelligenceConstants {
    
    /// Event data keys used by the intelligence preprocessor
    enum EventDataKeys {
        static let RELEVANCE = "intelligence.relevance"
        static let COMMERCE_ACTION = "intelligence.commerceAction"
        static let CATEGORY = "intelligence.category"
        static let ITEM_ID = "intelligence.itemId"
        static let ITEM_NAME = "intelligence.itemName"
        static let ITEM_PRICE = "intelligence.itemPrice"
        static let WEIGHT = "intelligence.weight"
    }
    
    /// Configuration keys
    enum ConfigKeys {
        static let ENABLED = "intelligence.enabled"
        static let DOMAIN = "intelligence.domain"
        static let EVENT_TYPES = "intelligence.eventTypes"
        static let PROVIDER = "intelligence.provider"
    }
    
    /// XDM event paths
    enum XDM {
        static let EVENT_TYPE = "eventType"
        static let COMMERCE = "commerce"
        static let PRODUCT_LIST_ITEMS = "productListItems"
        
        // Commerce actions
        static let PRODUCT_VIEWS = "productViews"
        static let PRODUCT_LIST_VIEWS = "productListViews"
        static let PRODUCT_LIST_ADDS = "productListAdds"
        static let PRODUCT_LIST_REMOVALS = "productListRemovals"
        static let PURCHASES = "purchases"
        
        // Product fields
        static let SKU = "SKU"
        static let NAME = "name"
        static let PRICE_TOTAL = "priceTotal"
        static let PRODUCT_CATEGORIES = "productCategories"
    }
    
    /// Commerce action mappings
    enum CommerceAction {
        static let PRODUCT_VIEW = "productView"
        static let ADD_TO_CART = "addToCart"
        static let REMOVE_FROM_CART = "removeFromCart"
        static let PURCHASE = "purchase"
    }
    
    /// Event weights for personalization scoring
    enum EventWeights {
        static let PRODUCT_VIEW: Double = 1.0
        static let ADD_TO_CART: Double = 3.0
        static let REMOVE_FROM_CART: Double = -1.0
        static let PURCHASE: Double = 5.0
        static let LIFECYCLE: Double = 0.5
        static let CUSTOM: Double = 1.0
    }
}
