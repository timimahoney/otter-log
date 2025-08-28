//
//  Analytics.swift
//  Otter
//
//  Created by Tim Mahoney on 2/28/24.
//

import Foundation
import Mixpanel

typealias AnalyticsProperties = Properties

class Analytics {
    
    public static func track(
        _ eventName: String,
        _ properties: AnalyticsProperties = [:]
    ) {
        Task(priority: .background) {
            Logger.analytics.debug("Will log event \(eventName) with properties \(properties)")
            Self.mixpanel.track(event: eventName, properties: properties)
        }
    }
}

// MARK: - Event / Property Strings

extension String {
    public static let analytics_speed: String = "Speed"
    public static let analytics_speedActivitiesInRange: String = "Speed_FilterInRange"
    public static let analytics_entryCount: String = "EntryCount"
    public static let analytics_activityCount: String = "ActivityCount"
    public static let analytics_colorizationCount: String = "ColorizationCount"
    public static let analytics_colorizationName: String = "ColorizationName"
    public static let analytics_filteredCount: String = "FilteredCount"
    public static let analytics_dateRange: String = "DateRange"
    public static let analytics_selection: String = "Selection"
    public static let analytics_queryStructureRaw: String = "QueryStructure_Raw"
    public static let analytics_queryStructureOptimized: String = "QueryStructure_Optimized"
    public static let analytics_topLevelCompoundQuery: String = "TopLevelCompoundQuery"
    public static func analytics_subqueryCount(_ typeName: String) -> String { "SubqueryCount_\(typeName)" }
    public static let analytics_subqueryCountTotal = "SubqueryCount_Total"
    public static let analytics_subqueryCountOptimized = "SubqueryCount_Optimized"
    public static let analytics_filterStringSize: String = "FilterStringSize"
    public static let analytics_showInspector: String = "ShowInspector"
    public static let analytics_format: String = "Format"
    public static let analytics_compoundVariant: String = "CompoundVariant"
    public static let analytics_subqueryType: String = "SubqueryType"
    public static func analytics_speedForDateRange(_ dateRange: DateRange) -> String { "Speed (\(dateRange.nameKey))" }
    public static let analytics_statName: String = "StatName"
    public static let analytics_property: String = "Property"
    public static let analytics_comparison: String = "Comparison"
    
    public static let analytics_errorDomain: String = "ErrorDomain"
    public static let analytics_errorCode: String = "ErrorCode"
    
    public static let analytics_savedFilterCount: String = "SavedFilterCount"
}

// MARK: - Mixpanel

extension Analytics {
    
    private static let mixpanelProjectToken = "YOUR_MIXPANEL_TOKEN_HERE"
    
    private static var mixpanel: MixpanelInstance {
        Self.ensureInitialized()
        return Mixpanel.mainInstance()
    }
    
    private static var isInitialized = OSAllocatedUnfairLock(initialState: false)
    private static func ensureInitialized() {
        self.isInitialized.withLock {
            if !$0 {
                Mixpanel.initialize(token: Self.mixpanelProjectToken)
                $0 = true
            }
        }
    }
}

// MARK: - Extensions

extension Subquery {
    
    /// A set of analytics properties that represent the analytics-related aspects of a query.
    /// For example, this will include the query structure and the optimized query structure.
    var analyticsProperties: AnalyticsProperties {
        var properties: AnalyticsProperties = [
            .analytics_queryStructureRaw: self.analyticsStructure,
            .analytics_subqueryCountTotal: self.recursiveQueries.count,
        ]
        
        if case .compound(let compound) = self {
            properties[.analytics_topLevelCompoundQuery] = compound.variant.analyticsSymbol
        }
        
        if let optimized = self.optimized() {
            properties[.analytics_queryStructureOptimized] = optimized.analyticsStructure
            
            // Count the number of each type of query in all the subqueries.
            let recursiveQueries = optimized.recursiveQueries
            let subqueryCounts = recursiveQueries.reduce(into: [:]) { $0[$1.analyticsType, default: 0] += 1 }
            for (type, count) in subqueryCounts {
                properties[.analytics_subqueryCount(type)] = count
            }
            properties[.analytics_subqueryCountOptimized] = recursiveQueries.count
        }
        
        return properties
    }
    
    /// A string that we send through our analytics that represents the structure of this query.
    /// This strips all the user-entered text and maintains the structure.
    /// For example, this query:
    ///
    /// (subsystem == "hello") && (process == "world")
    public var analyticsStructure: String {
        switch self {
        case .property(let property):
            return property.analyticsStructure
        case .compound(let compound):
            return compound.analyticsStructure
        case .logLevel(let logLevel):
            return logLevel.analyticsStructure
        }
    }
    
    public var analyticsType: String {
        switch self {
        case .compound(let compound):
            return compound.variant.symbol
        case .logLevel:
            return "LogLevel"
        case .property(let property):
            return property.property.name
        }
    }
}

extension PropertyQuery {
    var analyticsStructure: String {
        return "(\(self.property.name.lowercased()) \(self.comparison.analyticsSymbol))"
    }
}

extension CompoundQuery {
    var analyticsStructure: String {
        let subqueryDescriptions = self.subqueries.map { $0.analyticsStructure }.joined(separator: " \(self.variant.symbol) ")
        return "(\(subqueryDescriptions))"
    }
}

extension LogLevelQuery {
    var analyticsStructure: String {
        let sortedLevels = self.logLevels.sorted { $0.rawValue < $1.rawValue }
        let levelsString = sortedLevels.map { $0.description.lowercased() }.joined(separator: "|")
        return "(level in \(levelsString))"
    }
}

extension CompoundQuery.Variant {
    public var analyticsSymbol: String { self.symbol }
}
