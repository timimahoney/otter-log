//
//  FilteredData.swift
//  Otter
//
//  Created by Tim Mahoney on 2/6/24.
//

import Foundation

/// An object that holds log data from the database, possibly scoped to a query or something else.
///
/// For example, each window might have its own `FilteredData` that it shows in the UI.
/// You can also create a `FilteredData` for the entire database by having no filter.
public struct FilteredData : Sendable {
    
    /// The database being used as the source for data.
    public var database: Database
    
    /// A unique ID of this filtered data object.
    let id = UUID()
    
    public init(_ database: Database) {
        self.database = database
    }
    
    // MARK: - Scoped Data
    
    /// The entries filtered by whatever scope this `FilteredData` is using.
    /// This is the list of entries that should be shown in the UI.
    ///
    /// This is essentially derived from this:
    /// 1. Take all the entries in the whole database.
    /// 2. Get only those entries within the desired date range.
    /// 3. Filter those entries by the user's query.
    /// 4. Further filter entries if the user has selected any activities.
    public var entries: [Entry] = []
    
    /// The activities included in this filtered view of the database.
    /// This includes all activities in the selected date range that match the query.
    ///
    /// Note that `entries` is further-filtered by the current user-selected activities.
    /// This means that the activities in `entries` might be a subset of those in `activities`.
    public var activities: [Activity] = []
    
    /// All the activities in the visible list of activities, recursively including subactivities.
    public var recursiveActivitiesByID: [Activity.ID : Activity] = [:]
    
    /// The date the entries were last regenerated.
    public var lastRegenerateEntriesDate: Date = .distantPast
    
    /// The date the activities were last regenerated.
    public var lastRegenerateActivitiesDate: Date = .distantPast
    
    // MARK: - Filter
    
    /// The query set by the user.
    public var query: Subquery? {
        didSet {
            if self.query != oldValue {
                Logger.filteredData.debug("Invalidating cached query filtered entries after setting query")
                self.cachedQueryFilteredEntries = nil
            }
        }
    }
    
    /// The date range of all the entries in the filtered database.
    ///
    /// Note that this is invalid if either bound is `.distantPast` or `.distantFuture`.
    public var userSelectedRange: ClosedRange<Date> = .distantPast ... .distantFuture {
        didSet {
            if self.userSelectedRange != oldValue {
                Logger.filteredData.debug("Invalidating user-selected and query-filtered entry cache after setting user selected range")
                self.cachedEntriesInRange = nil
                self.cachedQueryFilteredEntries = nil
            }
        }
    }
    
    /// The activities that were selected by the user in the UI.
    public var selectedActivityIDs: Set<Activity.ID> = [] {
        didSet {
            if self.selectedActivityIDs != oldValue {
                self.hasNewSelectedActivityIDs = true
            }
        }
    }
    private var hasNewSelectedActivityIDs = false
    
    public var activityFilter: String = "" {
        didSet {
            if self.activityFilter != oldValue {
                self.needsToRegenerateActivities = true
            }
        }
    }

    // MARK: - Cache
    
    /// The range of the data in the database.
    /// If either bound is `.distantPast` or `.distantFuture`, this is an invalid range.
    private var databaseRange: ClosedRange<Date> = .distantPast ... .distantFuture
    
    /// The date of the earliest known entry.
    /// This is different from `databaseRange` because `databaseRange` might be populated before we've actually loaded all our entries.
    private var earliestEntryDate: Date = .distantFuture
    
    /// A cached list of the entries from `cachedEntriesInUserSelectedRange`, further filtered by the user query.
    /// This is just a cached list so that we don't have to filter again when the user selects an activity.
    private var cachedQueryFilteredEntries: [Entry]?
    
    /// The entries from the database that are within the user-specified date range.
    /// Keep this cached list so we don't have to filter by date when the user changes their query.
    /// If this is `nil`, then we need to get a new set of entries from the database.
    private var cachedEntriesInRange: [Entry]?
    
    /// All activities from the database that are within the user-specified range (generated from `cachedEntriesInRange`).
    /// These are all the activities recursively, not just the top-level activities.
    /// We use this as the starting point to creating `activities` based on the actual user-visible entries.
    private var cachedRecursiveActivitiesInRange: [Activity]?
    
    /// True if we need to regenerate the list of activities from the queried results.
    private var needsToRegenerateActivities: Bool = true
}

// MARK: - Hashable / Equatable

extension FilteredData : Hashable {
    
    public func hash(into hasher: inout Hasher) {
        self.id.hash(into: &hasher)
        self.lastRegenerateEntriesDate.hash(into: &hasher)
        self.lastRegenerateActivitiesDate.hash(into: &hasher)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Implement this in a cheaper way so that SwiftUI doesn't hang trying to compare it all the time.
        return lhs.id == rhs.id &&
        lhs.lastRegenerateEntriesDate == rhs.lastRegenerateEntriesDate &&
        lhs.lastRegenerateActivitiesDate == rhs.lastRegenerateActivitiesDate
    }
}

// MARK: - Updating Data

extension FilteredData {
    
    /// Updates the filtered entries and activities from the database if necessary.
    /// If there's nothing to update, this might be essentially a no-op.
    public mutating func regenerateEntries(progress: Progress = Progress()) async throws {
        let measurementStart = Date.now
        
        self.updateDatabaseRange()
        
        if self.cachedEntriesInRange != nil &&
            self.cachedQueryFilteredEntries != nil &&
            !self.needsToRegenerateActivities &&
            !self.hasNewSelectedActivityIDs
        {
            Logger.filteredData.debug("Nothing to filter")
            return
        }
        
        progress.totalUnitCount = 100
        progress.completedUnitCount = 0
        
        let dateRangeEntries = self.allEntriesInUserSelectedRange()
        
        // First, filter the entries based on the user's query.
        let queryFilteredEntries: [Entry] = try await self.filterByQuery(dateRangeEntries, overallProgress: progress)
        
        // Filter the logs we show based on the selected activities as well.
        let newEntries = try await self.filterBySelectedActivities(queryFilteredEntries)
        
        try Task.checkCancellation()
        
        Logger.filteredData.info("Regenerated entries in \(measurementStart.secondsSinceNowString). entries=\(newEntries.count.formatted())")
        
        // Now that we've calculated the changes, show them in the UI.
        self.entries = newEntries
        self.hasNewSelectedActivityIDs = false
        self.lastRegenerateEntriesDate = .now
    }
    
    mutating func filterByQuery(_ entriesToFilter: [Entry], overallProgress: Progress) async throws -> [Entry] {
        if let existingFilteredEntries = self.cachedQueryFilteredEntries {
            return existingFilteredEntries
        } else {
            let newQueryFilteredEntries: [Entry]
            if let query = self.query {
                let processingStart = Date.now
                
                let filterStart = Date.now
                let filterProgress = Progress()
                overallProgress.addChild(filterProgress, withPendingUnitCount: 100)
                newQueryFilteredEntries = try await Database.filterEntries(
                    entriesToFilter,
                    matching: query,
                    progress: filterProgress
                )
                Logger.filteredData.info("Re-filtered entries by user query in \(filterStart.secondsSinceNowString)")
                
                let speed = -processingStart.timeIntervalSinceNow
                var properties: AnalyticsProperties = [
                    .analytics_speed : speed,
                    .analytics_dateRange : self.userSelectedRange.timeInterval,
                    .analytics_entryCount: entriesToFilter.count,
                    .analytics_filteredCount: newQueryFilteredEntries.count,
                ]
                properties.merge(query.analyticsProperties) { $1 }
                Analytics.track("Filter by Query", properties)
            } else {
                newQueryFilteredEntries = entriesToFilter
            }
            
            self.cachedQueryFilteredEntries = newQueryFilteredEntries
            self.cachedRecursiveActivitiesInRange = nil
            self.needsToRegenerateActivities = true
            return newQueryFilteredEntries
        }
    }
    
    func filterBySelectedActivities(_ entriesToFilter: [Entry]) async throws -> [Entry] {
        let result: [Entry]
        
        // Get all the activities recursively under the selected activities.
        let activitiesByID = self.recursiveActivitiesByID
        let selectedActivityIDs = self.selectedActivityIDs
        let explicitlySelectedActivities = selectedActivityIDs.compactMap { activitiesByID[$0] }
        let recursiveSelectedActivityIDs: Set<Activity.ID> = explicitlySelectedActivities.reduce(into: []) { $0.formUnion($1.recursiveSubactivityIDsIncludingSelf) }
        
        if recursiveSelectedActivityIDs.isEmpty {
            result = entriesToFilter
        } else {
            let selectedActivitiesStart = Date.now
            result = entriesToFilter.ot_concurrentFilter { recursiveSelectedActivityIDs.contains($0.activityIdentifier) }
            try Task.checkCancellation()
            Logger.filteredData.debug("Filtered \(selectedActivityIDs.count.formatted()) selected activities in \(selectedActivitiesStart.secondsSinceNowString)")
        }
        
        return result
    }
    
    /// Returns all the entries in the user-selected range.
    /// This caches data internally. It might return a cached version, or it might recalculate the value.
    private mutating func allEntriesInUserSelectedRange() -> [Entry] {
        // Make sure we have our cache of entries filtered by date range.
        let dateRangeEntries: [Entry]
        
        if let entriesInDateRange = self.cachedEntriesInRange {
            dateRangeEntries = entriesInDateRange
        } else {
            let start = self.userSelectedRange.lowerBound
            let end = self.userSelectedRange.upperBound
            if start...end == self.database.range {
                dateRangeEntries = self.database.entries
            } else {
                let algorithmStartDate = Date.now
                let allEntries = self.database.entries
                let startIndex = self.binarySearchIndexAfterDate(allEntries, target: start) ?? allEntries.startIndex
                let endIndex = self.binarySearchIndexAfterDate(allEntries, target: end) ?? allEntries.endIndex
                dateRangeEntries = Array(allEntries[startIndex..<endIndex])
                
                let speed = -algorithmStartDate.timeIntervalSinceNow
                Analytics.track("Filter Entries In Range", [
                    .analytics_speed : speed,
                    .analytics_dateRange : self.userSelectedRange.timeInterval,
                    .analytics_entryCount : allEntries.count,
                    .analytics_filteredCount : dateRangeEntries.count,
                ])
            }
            
            self.cachedEntriesInRange = dateRangeEntries
            
            // If we're re-generating the data from the date range, we'll need to re-query them too.
            // We also need to re-generate the activities in the range.
            self.cachedQueryFilteredEntries = nil
            self.cachedRecursiveActivitiesInRange = nil
            self.needsToRegenerateActivities = true
        }
        
        return dateRangeEntries
    }
    
    func binarySearchIndexAfterDate(_ entries: [Entry], target: Date) -> Array<Entry>.Index? {
        var low = 0
        var high = entries.count - 1
        var result: Array<Entry>.Index?
        
        while low <= high {
            let mid = low + (high - low) / 2
            
            let entryDate = entries[mid].date
            if entryDate >= target {
                result = mid
                high = mid - 1 // Search for the first occurrence
            } else if entryDate < target {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        return result
    }
    
    // MARK: - Activities
    
    public mutating func regenerateActivities() throws {
        try Task.checkCancellation()
        
        var activitiesInRangeSpeed: TimeInterval?
        let activitiesInRange: [Activity]
        if let cachedActivities = self.cachedRecursiveActivitiesInRange {
            activitiesInRange = cachedActivities
        } else if let entriesInRange = self.cachedEntriesInRange {
            // We want to cache the recursive list of activities, not just the top-level ones.
            let inRangeStart = Date.now
            let topLevelActivities = Activity.fromEntries(entriesInRange)
            activitiesInRange = try topLevelActivities.reduce(into: []) {
                try Task.checkCancellation()
                $0.append(contentsOf: $1.recursiveSubactivitiesIncludingSelf)
            }
            self.cachedRecursiveActivitiesInRange = activitiesInRange
            self.needsToRegenerateActivities = true
            try Task.checkCancellation()
            
            activitiesInRangeSpeed = -inRangeStart.timeIntervalSinceNow
        } else {
            Logger.filteredData.error("No cached entries when trying to generate activities")
            activitiesInRange = []
        }
        
        if self.needsToRegenerateActivities {
            let start = Date.now
            
            let isEmptyQuery = (self.query?.isEmpty ?? true)
            let entriesToCompare = isEmptyQuery ? nil : self.cachedQueryFilteredEntries
            let newActivities = Database.filterActivities(activitiesInRange, entries: entriesToCompare, filter: self.activityFilter)
            try Task.checkCancellation()
            
            self.activities = newActivities
            let recursiveActivitiesToShow = newActivities.reduce(into: []) { $0.append(contentsOf: $1.recursiveSubactivitiesIncludingSelf) }
            let recursiveActivities = recursiveActivitiesToShow.reduce(into: [:]) { $0[$1.id] = $1 }
            self.recursiveActivitiesByID = recursiveActivities
            
            // Make sure we don't have any "selected" activities that are no longer in our list of activities.
            self.selectedActivityIDs = self.selectedActivityIDs.filter { recursiveActivities[$0] != nil }
            
            let speed = -start.timeIntervalSinceNow
            Analytics.track("Regenerate Activities", [
                .analytics_speed : speed,
                .analytics_speedActivitiesInRange : activitiesInRangeSpeed ?? 0,
                .analytics_dateRange : self.userSelectedRange.timeInterval,
                .analytics_entryCount: self.cachedQueryFilteredEntries?.count ?? 0,
                .analytics_activityCount: activitiesInRange.count,
                .analytics_filteredCount: newActivities.count,
                .analytics_filterStringSize: self.activityFilter.count
            ])
            
            Logger.filteredData.debug("Regenerated activities (\(newActivities.count.formatted())) in \(start.secondsSinceNowString)")
            self.needsToRegenerateActivities = false
            self.lastRegenerateActivitiesDate = Date.now
        }
    }
    
    // MARK: - Other
    
    /// Updates the current database range from the database.
    public mutating func updateDatabaseRange() {
        let databaseRange = self.database.range
        let previousRange = self.databaseRange
        if databaseRange != previousRange {
            // We need to replace the new database range.
            // If the new range potentially includes new data in the user-visible range, let's clear the cache.
            if previousRange.lowerBound > self.userSelectedRange.lowerBound {
                Logger.filteredData.debug("Invalidating entry cache after updating database range in user-selected range")
                self.cachedQueryFilteredEntries = nil
                self.cachedEntriesInRange = nil
            }
            self.databaseRange = databaseRange
        }
        
        if let firstEntry = self.database.entries.first {
            if self.earliestEntryDate > firstEntry.date {
                if self.earliestEntryDate > self.userSelectedRange.lowerBound {
                    Logger.filteredData.debug("Invalidating entry cache after updating earliest known entry date")
                    self.cachedQueryFilteredEntries = nil
                    self.cachedEntriesInRange = nil
                }
                self.earliestEntryDate = firstEntry.date
            }
        }
    }
}
