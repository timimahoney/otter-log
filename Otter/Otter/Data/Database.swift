//
//  Database.swift
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

import Combine
import Foundation
import os.log
import os.signpost
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// A database of log entries.
///
/// Note that this class makes heavy assumptions that things are always sorted.
/// If there are bugs, that might not be true...
public final class Database : Sendable {
    
    @AppStorage("OTSlowLoading") static var slowLoading: Bool = false
    
    public var configuration: Configuration {
        get { self._configuration.withLock { $0 } }
        set { self._configuration.withLock { $0 = newValue } }
    }
    private let _configuration: OSAllocatedUnfairLock<Configuration>
    
    public var inProgressArchiveURLs: [URL] {
        get { self._inProgressArchiveURLs.withLock { $0 } }
        set { self._inProgressArchiveURLs.withLock { $0 = newValue } }
    }
    private let _inProgressArchiveURLs = OSAllocatedUnfairLock<[URL]>(initialState: [])
    
    public var entries: [Entry] {
        get { self._entries.withLock { $0 } }
        set { self._entries.withLock { $0 = newValue } }
    }
    private let _entries = OSAllocatedUnfairLock<[Entry]>(initialState: [])
    
    public var range: ClosedRange<Date> {
        get { self._range.withLock { $0 } }
        set { self._range.withLock { $0 = newValue } }
    }
    private let _range = OSAllocatedUnfairLock(initialState: Date.distantPast...Date.distantFuture)
    
    public init(configuration: Configuration) {
        self._configuration = .init(initialState: configuration)
    }
    
    convenience public init(entries: [Entry] = []) {
        self.init(configuration: .init())
        let sortedEntries = entries.sorted { $0.date < $1.date }
        self.add(sortedEntries)
    }
}

// MARK: - ReferenceFileDocument

enum DatabaseError : Error {
    case cannotWriteFiles
}

extension Database: ReferenceFileDocument {
    
    public static var readableContentTypes: [UTType] = [ .logarchive ]
    
    public struct Snapshot {
        var configuration: Configuration
    }
    
    convenience public init(configuration: ReadConfiguration) throws {
        let temporaryFileURL = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString).appendingPathExtension("logarchive")
        try configuration.file.write(to: temporaryFileURL, originalContentsURL: nil)
        self.init(configuration: .init(logarchiveURLs: [temporaryFileURL], deleteFileAfterLoading: true))
    }
    
    public func snapshot(contentType: UTType) throws -> Snapshot {
        return Snapshot(configuration: self.configuration)
    }
    
    public func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper  {
        Logger.data.fault("Trying to save a file. Why on earth would you do that?")
        Analytics.track("Save File")
        throw DatabaseError.cannotWriteFiles
    }
}

// MARK: - Logging

extension Database : CustomStringConvertible {
    public var description: String { "Database(\(self.configuration))" }
}

// MARK: - Configuration

extension Database {

    public struct Configuration : Codable, Hashable {
        var logarchiveURLs: Set<URL> = []
        var deleteFileAfterLoading = false
    }
}

extension Database.Configuration : CustomStringConvertible {
    public var description: String { "Configuration(\(self.key))" }
}

extension Database.Configuration {
    
    // A unique ID for this database to use in the shared database cache.
    var key: String { self.logarchiveURLs.map { $0.path() }.sorted().joined(separator: "|") }
}

extension Database {
    
    func deleteAllData() async throws {
        let newEntries = [Entry]()
        self.entries = newEntries
    }
}

// MARK: - Loading

extension Database {
    
    public func addLogarchive(_ fileURL: URL) {
        if self.configuration.logarchiveURLs.contains(fileURL) {
            Logger.data.info("Already know about log archive at \(fileURL)")
            return
        } else {
            Logger.data.log("Adding log archive at \(fileURL)")
            self.configuration.logarchiveURLs.insert(fileURL)
        }
    }
    
    public func loadLogarchivesIfNecessary(
        slow: Bool? = nil,
        progresses: (([DateRange : Progress]) -> ())? = nil,
        updatedDatabaseRange: ((ClosedRange<Date>) -> ())? = nil,
        chunkLoaded: ((ClosedRange<Date>) -> ())? = nil
    ) async throws {
        Logger.data.info("Will load logs if necessary")
        for url in self.configuration.logarchiveURLs {
            try await self.loadLogarchiveIfNecessary(from: url, slow: slow, progresses: progresses, updatedDatabaseRange: updatedDatabaseRange, chunkLoaded: chunkLoaded)
        }
    }
    
    public func loadLogarchiveIfNecessary(
        from fileURL: URL,
        slow: Bool? = nil,
        progresses: (([DateRange : Progress]) -> ())? = nil,
        updatedDatabaseRange: ((ClosedRange<Date>) -> ())?,
        chunkLoaded: ((ClosedRange<Date>) -> ())? = nil
    ) async throws {
        // Use the existence of a loading state in the dictionary as an indication that loading has begun.
        let shouldLoad = self._inProgressArchiveURLs.withLock {
            if $0.contains(fileURL) {
                return false
            } else {
                $0.append(fileURL)
                return true
            }
        }
        if !shouldLoad {
            Logger.data.info("Not loading logs because we're already loading \(fileURL)")
            return
        }
        
        Logger.data.log("Will import logs from file \(fileURL)")
        let slow = slow ?? Self.slowLoading
        if slow {
            try await self.loadSlow(from: fileURL, progresses: progresses, updatedDatabaseRange: updatedDatabaseRange, chunkLoaded: chunkLoaded)
        } else {
            do {
                try await self.loadFast(from: fileURL, progresses: progresses, updatedDatabaseRange: updatedDatabaseRange, chunkLoaded: chunkLoaded)
            } catch {
                Logger.data.fault("Falling back to slow loading: \(error)")
                try await self.loadSlow(from: fileURL, progresses: progresses, updatedDatabaseRange: updatedDatabaseRange, chunkLoaded: chunkLoaded)
            }
        }
        
        if self.configuration.deleteFileAfterLoading {
            Logger.data.log("Deleting temporary file after loading: \(fileURL)")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: Fast Loading
    
    private func loadFast(
        from fileURL: URL,
        progresses progressesBlock: (([DateRange : Progress]) -> ())?,
        updatedDatabaseRange: ((ClosedRange<Date>) -> ())?,
        chunkLoaded: ((ClosedRange<Date>) -> ())? = nil
    ) async throws {
        let speedStart = Date.now
        do {
            try await self._loadFast(from: fileURL, progresses: progressesBlock, updatedDatabaseRange: updatedDatabaseRange, chunkLoaded: chunkLoaded)
        } catch {
            Logger.data.fault("Fast load failed: \(error)")
            
            let speed = -speedStart.timeIntervalSinceNow
            var properties: AnalyticsProperties = [
                .analytics_speed: speed,
            ]
            let nsError = error as NSError
            properties[.analytics_errorDomain] = nsError.domain
            properties[.analytics_errorCode] = nsError.code
            Analytics.track("Load Fast Failed", properties)
            
            // Rethrow
            throw error
        }
    }
    
    private func _loadFast(
        from fileURL: URL,
        progresses progressesBlock: (([DateRange : Progress]) -> ())?,
        updatedDatabaseRange: ((ClosedRange<Date>) -> ())?,
        chunkLoaded: ((ClosedRange<Date>) -> ())? = nil
    ) async throws {
        let loadingStartDate = Date.now
        let finishedChunkIndexesLock = OSAllocatedUnfairLock(initialState: IndexSet())
        let finishedChunksLock = OSAllocatedUnfairLock<[Int : [Entry]]>(initialState: [:])
        let knownProcesses = OSAllocatedUnfairLock<[UUID : String]>(initialState: [:])
        let processChunksTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
        
        let loadingRanges: [DateRange] = [ .fiveMinutes, .thirtyMinutes, .hour, .fourHours, .eightHours, .day, .all ]
        let progresses: [DateRange : Progress] = loadingRanges.reduce(into: [:]) { $0[$1] = Progress() }
        progressesBlock?(progresses)
        
        let nsProgresses: [NSNumber : Progress] = progresses.reduce(into: [:]) {
            let key = $1.key.timeIntervalBeforeEnd ?? -1
            $0[NSNumber(floatLiteral: key)] = $1.value
        }
        
        var dateRangeSpeeds: [DateRange : TimeInterval] = [:]
        
        try await OtterFastEnumeration.fastEnumerate(fileURL, progresses: nsProgresses) { start, end in
            self.range = start...end
            updatedDatabaseRange?(self.range)
        } block: { chunkIndex, logEntry in
            if let entry = Entry(systemEntry: logEntry, knownProcesses: knownProcesses) {
                return EntryBox(entry)
            } else {
                return nil
            }
        } finishedChunk: { finishedChunkIndex, chunkCount, nsChunkEntries in
            let possiblyUnsortedEntries = nsChunkEntries.compactMap { ($0 as? EntryBox)?.entry }
            if possiblyUnsortedEntries.count != nsChunkEntries.count {
                Logger.data.fault("WHAT'S IN THE BOX?! \(possiblyUnsortedEntries.count.formatted()) OR \(nsChunkEntries.count.formatted())?!?!?")
            }
            
            // When we finish a batch, we want to sort it.
            // Sorting piece by piece like this makes the end sort faster.
            // Not sure why we actually end up with un-sorted entries though.
            // TODO: Figure out why?
            let sortedEntries = possiblyUnsortedEntries.sorted { $0.date < $1.date }
            finishedChunksLock.withLock { finishedChunks in
                finishedChunks[finishedChunkIndex] = sortedEntries
                _ = finishedChunkIndexesLock.withLock { $0.insert(finishedChunkIndex) }
            }
            
            for (dateRange, progress) in progresses {
                if progress.fractionCompleted >= 1 && dateRangeSpeeds[dateRange] == nil {
                    dateRangeSpeeds[dateRange] = -loadingStartDate.timeIntervalSinceNow
                }
            }
            
            processChunksTask.withLock { task in
                let previousTask = task
                task = Task.detached(priority: .userInitiated) {
                    _ = await previousTask?.result
                    
                    // We want to incrementally show the most recent data as fast as possible.
                    finishedChunksLock.withLock { finishedChunks in
                        let finishedChunkIndexes = finishedChunkIndexesLock.withLock { $0 }
                        
                        // Make sure we've already loaded all the batches up until this one.
                        // We don't want to add them out of order.
                        var finishedEntries: [Entry] = []
                        
                        let lastFinishedIndex = finishedChunkIndexes.last ?? 0
                        for i in 0...lastFinishedIndex {
                            if finishedChunkIndexes.contains(i) {
                                if let chunkEntries = finishedChunks[i] {
                                    finishedChunks[i] = nil
                                    finishedEntries = chunkEntries + finishedEntries
                                }
                            } else {
                                // We found a batch index before the finished batch that hasn't finished yet.
                                // We'll have to wait until later.
                                Logger.data.debug("Finished batch with previous batches unfinished \(finishedChunkIndex)")
                                break
                            }
                        }
                        
                        if !finishedEntries.isEmpty {
                            Logger.data.debug("Will append new finished batches with \(finishedEntries.count.formatted()) entries")
                            self.add(finishedEntries, prepend: true)
                            if let first = finishedEntries.first?.date, let last = finishedEntries.last?.date {
                                // We might get a single entry, which is an invalid date range.
                                let sanitizedLast = last > first ? last : first + 1
                                chunkLoaded?(first...sanitizedLast)
                            } else {
                                chunkLoaded?(.distantRange)
                            }
                        }
                    }
                }
            }
        }
        
        // We didn't necessarily add all the finished chunks incrementally above.
        // Let's clean up and add all the other ones.
        // By this point, each chunk should be sorted on its own, so we can just concatenate them in the right order.
        let remainingEntries: [Entry] = finishedChunksLock.withLock { $0 }.sorted { $0.key > $1.key }.flatMap { $0.value }
        self.add(remainingEntries, prepend: true)
        
        let entryCount = self.entries.count
        let speed = -loadingStartDate.timeIntervalSinceNow
        Logger.data.info("Finished fast-loading \(entryCount.formatted()) entries in \(speed.secondsString)")
        
        var properties: AnalyticsProperties = [
            .analytics_entryCount : entryCount,
            .analytics_speed: speed,
            .analytics_dateRange: self.range.timeInterval,
        ]
        for (range, speed) in dateRangeSpeeds {
            properties[.analytics_speedForDateRange(range)] = speed
        }
        Analytics.track("Load Fast", properties)
    }
    
    // MARK: Slow Loading
    
    private func loadSlow(
        from fileURL: URL,
        progresses progressesBlock: (([DateRange : Progress]) -> ())?,
        updatedDatabaseRange: ((ClosedRange<Date>) -> ())?,
        chunkLoaded: ((ClosedRange<Date>) -> ())? = nil
    ) async throws {
        // Wrap our actual call so that we can post an analytics event when we fail.
        let speedStart = Date.now
        do {
            try await self._loadSlow(from: fileURL, progresses: progressesBlock, updatedDatabaseRange: updatedDatabaseRange, chunkLoaded: chunkLoaded)
        } catch {
            Logger.data.fault("Slow load failed: \(error)")
            
            let speed = -speedStart.timeIntervalSinceNow
            var properties: AnalyticsProperties = [
                .analytics_speed: speed,
            ]
            let nsError = error as NSError
            properties[.analytics_errorDomain] = nsError.domain
            properties[.analytics_errorCode] = nsError.code
            Analytics.track("Load Slow Failed", properties)
            
            // Rethrow
            throw error
        }
    }
    
    private func _loadSlow(
        from fileURL: URL,
        progresses progressesBlock: (([DateRange : Progress]) -> ())?,
        updatedDatabaseRange: ((ClosedRange<Date>) -> ())?,
        chunkLoaded: ((ClosedRange<Date>) -> ())? = nil
    ) async throws {
        Logger.data.log("Slow loading logs")
        
        // Our approach to loading in the slow path is a bit different than the fast path.
        //
        // In the fast path, we progressively load everything in chunks, and it all fits together nicely.
        // In the slow path, we load a few date ranges simultaneously, and replace the database contents as we go.
        // This allows us to progressively show more data in the UI.
        //
        // It's not as efficient (or fast) as the fast path, but it's relatively simple.
        // It also allows us to progressively show more and more data in the UI.
        // This gives the appearance of "speed" to the user.
        let loadingStartDate = Date.now
        
        let ranges: [DateRange] = [
            .fiveMinutes,
            .thirtyMinutes,
            .all,
        ]
        
        let dateRangeSpeeds: [DateRange : TimeInterval] = [:]
        let progresses = ranges.reduce(into: [:]) { $0[$1] = Progress() }
        progressesBlock?(progresses)
        
        var databaseStart: Date?
        var databaseEnd: Date?
        
        let updateDatabaseRangeIfNecessary = {
            if self.range == .distantRange {
                if let start = databaseStart, let end = databaseEnd {
                    self.range = start...end
                    updatedDatabaseRange?(self.range)
                }
            }
        }
        
        // Let's get the database start and end date first thing.
        let store = try OSLogStore(url: fileURL)
        if let range = try store.entryDateRange() {
            Logger.data.info("Got database range first \(range)")
            databaseStart = range.lowerBound
            databaseEnd = range.upperBound
            updateDatabaseRangeIfNecessary()
        }
        
        // Finally, load all the ranges.
        for range in ranges {
            guard let progress = progresses[range] else {
                Logger.data.fault("Failed to get progress for range: \(range)")
                continue
            }
            let rangeSpeedStart = Date.now
            
            let entries = try Self.loadSlowFromArchive(from: fileURL, range: range, progress: progress) { firstEntry in
                if databaseStart == nil && range == .all  {
                    let firstEntryDate = firstEntry.date
                    Logger.data.info("Got database start date \(firstEntryDate)")
                    databaseStart = firstEntryDate
                    updateDatabaseRangeIfNecessary()
                }
            }
            
            if databaseEnd == nil, let lastEntry = entries.last {
                let lastEntryDate = lastEntry.date
                Logger.data.info("Got database end date \(lastEntryDate)")
                databaseEnd = lastEntryDate
                updateDatabaseRangeIfNecessary()
            }
            
            // Finally, add this batch to the database.
            // Make sure to lock this since we don't want to accidentally replace more data with less.
            if let newFirstEntry = entries.first {
                var shouldReplace = false
                if let existingFirstEntry = self.entries.first {
                    shouldReplace = (newFirstEntry.date < existingFirstEntry.date)
                } else {
                    shouldReplace = true
                }
                
                if shouldReplace {
                    let sorted = entries.sorted { $0.date < $1.date }
                    self.entries = sorted
                    let first = sorted.first?.date ?? .distantFuture
                    let last = sorted.last?.date ?? .distantFuture
                    let range = first...last
                    chunkLoaded?(range)
                }
            }
            
            let batchSpeed = -rangeSpeedStart.timeIntervalSinceNow
            Logger.data.info("Finished loading range in \(batchSpeed.secondsString): \(range)")
        }
        
        updateDatabaseRangeIfNecessary()
        
        let entryCount = self.entries.count
        let speed = -loadingStartDate.timeIntervalSinceNow
        Logger.data.info("Finished loading (slow) \(entryCount.formatted()) entries in \(speed.secondsString)")
        
        var properties: AnalyticsProperties = [
            .analytics_entryCount : entryCount,
            .analytics_speed: speed,
            .analytics_dateRange: self.range.timeInterval,
        ]
        for (range, speed) in dateRangeSpeeds {
            properties[.analytics_speedForDateRange(range)] = speed
        }
        Analytics.track("Load Slow", properties)
    }
    
    private static func loadSlowFromArchive(
        from fileURL: URL,
        range: DateRange,
        progress: Progress,
        loadedFirstEntry: ((Entry) -> ())? = nil
    ) throws -> [Entry] {
        let speedStart = Date.now
        
        let activityPredidcate = NSPredicate(format: "eventType == activityCreateEvent")
        let notSubsystemPredicate = NSPredicate(format: "eventType == logEvent && !(subsystem IN %@)", argumentArray: [Self.subsystemsList])
        let subsystemPredicates = Self.subsystemsList.map { NSPredicate(format: "eventType == logEvent && subsystem == %@", argumentArray: [$0]) }
        let predicates = subsystemPredicates + [notSubsystemPredicate, activityPredidcate]
//        let subsystemPredicate = NSPredicate(format: "eventType == logEvent && subsystem IN %@", argumentArray: [Self.subsystemsList])
//        let predicates = [subsystemPredicate, notSubsystemPredicate, activityPredidcate]
        
        let allLoadedEntries = OSAllocatedUnfairLock<[Entry]>(initialState: [])
        let errorLock = OSAllocatedUnfairLock<Error?>(initialState: nil)
        
        DispatchQueue.concurrentPerform(iterations: predicates.count) { i in
            let predicate = predicates[i]
            do {
                let batchEntries = try self.loadSlowFromArchive_Batch_Unsorted(from: fileURL, range: range, predicate: predicate, progress: progress, loadedFirstEntry: loadedFirstEntry)
                allLoadedEntries.withLock { $0.append(contentsOf: batchEntries) }
            } catch {
                Logger.data.error("Loading individual batch failed: \(error)")
                errorLock.withLock {
                    if $0 == nil {
                        $0 = error
                    }
                }
            }
        }
        
        let entries = allLoadedEntries.withLock { $0 }
        progress.completedUnitCount = progress.totalUnitCount
        Logger.data.info("Finished loading (slow) range=(\(range)). \(entries.count.formatted()) entries in \(speedStart.secondsSinceNowString)")
        return entries
    }
    
    private static let subsystemsList = [
        "com.apple.bluetooth",
        "com.apple.mDNSResponder",
        "com.apple.runningboard",
        "com.apple.UIKit",
        "com.apple.xpc",
        "com.apple.cloudkit",
        "com.apple.WiFiManager",
    ]
    
    private static func loadSlowFromArchive_Batch_Unsorted(
        from fileURL: URL,
        range: DateRange,
        predicate: NSPredicate,
        progress: Progress,
        loadedFirstEntry: ((Entry) -> ())? = nil
    ) throws -> [Entry] {
        let predicateString = predicate.description
        Logger.data.debug("Starting to load (slow) with range: \(range) predicate=<\(predicate)>")
        
        let store = try OSLogStore(url: fileURL)
        var position: OSLogPosition?
        if let timeIntervalBeforeEnd = range.timeIntervalBeforeEnd {
            // Our span is "this much time from the end", and the API is "desired = me + timeInterval"
            position = store.position(timeIntervalSinceEnd: -timeIntervalBeforeEnd)
        }
        let osLogEntries = try store.getEntries(at: position, matching: predicate)
        
        // Track some things so that we can report progress.
        let loadingStartDate = Date.now
        let accumulatedCountLock = OSAllocatedUnfairLock(initialState: 0)
        let reportingInterval = 44_444
        
        var entries: [Entry] = []
        if let approximateCount = range.approximateLogCount {
            entries.reserveCapacity(approximateCount)
            progress.totalUnitCount = Int64(approximateCount)
        }
        
        var didLoadFirstEntry = false
        
        let predicateStart = Date.now
        for osLogEntry in osLogEntries {
            
            if let entry = Entry(osLogEntry: osLogEntry) {
                if !didLoadFirstEntry {
                    didLoadFirstEntry = true
                    loadedFirstEntry?(entry)
                }
                
                entries.append(entry)
                
                // Progress!
                accumulatedCountLock.withLock { count in
                    count += 1
                    if count % reportingInterval == 0 {
                        progress.completedUnitCount += Int64(count)
                        let speed = Double(count) / -loadingStartDate.timeIntervalSinceNow
                        Logger.data.debug("Progress loading (slow) entries for range=(\(range)) progress=(\(progress.completedUnitCount.formatted()) / ~\(progress.totalUnitCount.formatted())) speed=\(Int(speed).formatted())/s) predicate=<\(predicateString)>")
                        count = 0
                    }
                }
            }
        }
        
        Logger.data.debug("Loaded with predicate (slow) \(entries.count.formatted()) entries in \(predicateStart.secondsSinceNowString) for range=(\(range)) predicate=<\(predicateString)>")
        
        return entries
    }
}

// MARK: - Entries

extension Database {
    
    public func add(_ newEntries: [Entry], prepend: Bool = false, sort: Bool = false) {
        guard !newEntries.isEmpty else { return }
        self._entries.withLock { entries in
            if prepend {
                entries.insert(contentsOf: newEntries, at: 0)
            } else {
                entries.append(contentsOf: newEntries)
            }
            
            if sort {
                entries.sort { $0.date < $1.date }
            }
            
            let entryCount = entries.count
            Logger.data.info("Added \(newEntries.count.formatted()) entries. Now have \(entryCount.formatted())")
        }
    }
    
    static public func filterEntries(_ entries: [Entry], matching inQuery: Subquery, progress: Progress = Progress()) async throws -> [Entry] {
        if entries.isEmpty {
            Logger.data.debug("Returning empty array for filtering empty array with query: \(inQuery)")
            return []
        }
        guard let query = inQuery.optimized() else {
            Logger.data.debug("Returning all entries for empty query")
            return entries
        }
        
        Logger.data.info("Will filter \(entries.count.formatted()) entries: \(query)")
        let start = Date.now
        
        let context = FilterContext()
        
        let batchCount = 6
        let batchSize = max(entries.count / batchCount, 100)
        let reportingInterval = batchSize / 20
        progress.totalUnitCount = Int64(entries.count)
        
        let matches = try await withThrowingTaskGroup(of: (Int, [Entry]).self) { group in
            for batchStart in stride(from: 0, to: entries.count, by: batchSize) {
                group.addTask {
                    let batchEnd = min(batchStart + batchSize, entries.count)
                    let batch = Array(entries[batchStart..<batchEnd])
                    
                    var count = 0
                    let filtered = batch.filter {
                        // Report progress at some known interval.
                        count += 1
                        if count % reportingInterval == 0 {
                            DispatchQueue.main.sync {
                                progress.completedUnitCount += Int64(reportingInterval)
                            }
                        }
                        
                        return query.evaluate($0, context)
                    }
                    
                    try Task.checkCancellation()
                    
                    return (batchStart, filtered)
                }
            }
            
            let batchesBySortIndex: [Int : [Entry]] = try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
            let matches = batchesBySortIndex.enumerated().sorted { $0.element.key < $1.element.key }.flatMap { $0.element.value }
            return matches
        }
        
        try Task.checkCancellation()
        
        let duration = -start.timeIntervalSinceNow
        Logger.data.debug("Finished querying entries in \(duration.secondsString) for query: \(query)")
        return matches
    }
    
    static public func filterActivities(_ allActivities: [Activity], entries: [Entry]?, filter: String) -> [Activity] {
        // The activities sidebar shows all the top-level activities involved in the queried logs.
        // Let's find all the activities to show based on the query-filtered entries.
        let start = Date.now
        
        // We want to make sure every entry is accounted for in the list.
        // If there are no entries, then we can just take all the top-level activities.
        let entryStart = Date.now
        let activitiesToFilter: [Activity]
        if let entries {
            let entryActivityIDs = Set(entries.compactMap { $0.activityIdentifier })
            activitiesToFilter = allActivities.filter { entryActivityIDs.contains($0.id) }
        } else {
            activitiesToFilter = allActivities
        }
        
        // Filter this by the user's entered string.
        let filterStart = Date.now
        let stringFilteredActivities = filter.isEmpty ? activitiesToFilter : activitiesToFilter.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        
        // We don't want to show an activity at the top level if it's already present as a child in another top-level activity.
        // Construct a list of activities, keeping track of the set of included activities as we go.
        // If an entry's activity is already in the tree (if it's top-level parent is already in the list), skip it.
        let findTopLevelStart = Date.now
        var knownActivityIDs = Set<Activity.ID>()
        let result: [Activity] = stringFilteredActivities.reduce(into: []) {
            if !knownActivityIDs.contains($1.id) {
                $0.append($1)
                knownActivityIDs.formUnion(Set($1.recursiveSubactivityIDsIncludingSelf))
            }
        }
        
        Logger.data.debug("Filtered activities in \(start.secondsSinceNowString) entry=\(filterStart.timeIntervalSince(entryStart).secondsString) filter=\(filterStart.timeIntervalSince(findTopLevelStart).secondsString) findtoplevel=\(findTopLevelStart.secondsSinceNowString)")
        
        return result
    }
}
