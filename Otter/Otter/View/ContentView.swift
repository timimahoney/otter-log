//
//  ContentView.swift
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

import Combine
import SwiftUI
import os.log
import UniformTypeIdentifiers

struct ContentView: View {
    
    var database: Database
    @Environment(SavedQueries.self) var savedQueries
    
    // MARK: - User-modifiable state.
    
    @State var query: UserQuery = .init()
    @State var userSelectedRange: ClosedRange<Date> = .distantPast ... .distantFuture
    @State var selectedEntries: [Entry] = []
    @State var selectedActivityIDs: Set<Activity.ID> = []
    @State var activityFilter: String = ""
    
    /// The data shown in the UI.
    @State var data: FilteredData
    @State var stats: InspectorStats = .init()
    
    /// The progress of the current query filter.
    @State var entryFilterProgress: Progress?
    
    /// The progress of the current activity filter.
    @State var activityFilterProgress: Progress?
    
    /// The current progress loading the archive for the current date range.
    @State var loadingProgress: Progress? = Progress()
    
    /// All the loading progresses for all the date ranges.
    @State var loadingProgresses: [DateRange : Progress] = [:]
    
    // Timeline view state.
    @State var displayedDateRange: ClosedRange<Date> = .distantPast ... .distantFuture
    @State var dateToScroll: Date?
    
    // We use column visibility to determine whether to show the activity list spinner toolbar item.
    // Kinda clunky, but it works.
    @State var columnVisibility: NavigationSplitViewVisibility = .automatic
    
    @AppStorage("OTShowInspector") var isShowingInspector = true
    @AppStorage("OTSidebarWidth") var sidebarWidth = 224.0
    
    let regenerateEntriesCoalescer: Coalescer
    let regenerateActivitiesCoalescer: Coalescer
    let dataRegenerationLock = AsyncLock()
    
    public init(database: Database) {
        self.database = database
        self._data = State(initialValue: FilteredData(database))
        self.regenerateEntriesCoalescer = Coalescer()
        self.regenerateActivitiesCoalescer = Coalescer()
    }

    var body: some View {
        
        NavigationSplitView(columnVisibility: self.$columnVisibility) {
            
            GeometryReader { geometry in
                ActivityListView(
                    data: self.$data,
                    filter: self.$activityFilter,
                    selection: self.$selectedActivityIDs,
                    progress: self.$activityFilterProgress,
                    columnVisibility: self.$columnVisibility
                )
                .onChange(of: self.selectedActivityIDs) { oldValue, newValue in
                    self.coalescedRegenerateEntries(delay: 0, cancelPrevious: true)
                }
                .onChange(of: self.activityFilter) { oldValue, newValue in
                    self.coalescedRegenerateActivities(delay: 0.01)
                }
                .onChange(of: geometry.frame(in: .global).width) { oldValue, newValue in
                    self.sidebarWidth = newValue
                }
            }
            .navigationSplitViewColumnWidth(ideal: self.sidebarWidth)
            
        } detail: {
            
            VStack(spacing: 0) {
                
                //
                // Queries
                //
                QuerySectionView(query: self.$query)
                    .onChange(of: self.query.topLevelQuery) { oldValue, newValue in
                        Logger.ui.debug("Changed content view query")
                        self.coalescedRegenerateEntries(cancelPrevious: true)
                    }
                
                Divider()
                
                VSplitView {
                    //
                    // Entries
                    //
                    EntryListView(
                        data: self.$data,
                        colorizations: self.$query.colorizations,
                        displayedDateRange: self.$displayedDateRange,
                        dateToScroll: self.$dateToScroll,
                        onSelectionChange: { selectedEntries in
                            self.selectedEntries = selectedEntries
                        },
                        onSelectEntryMenuItem: { entryMenuItem in
                            self.modifyQueryForEntryMenuItem(entryMenuItem)
                        }
                    )
                    
                    //
                    // Timeline
                    //
                    TimelineView(
                        data: self.$data,
                        displayedDateRange: self.$displayedDateRange
                    ) { selectedDate in
                        self.dateToScroll = selectedDate
                    }
                    
                    //
                    // Bottom Bar
                    //
                    BottomBarView(
                        userSelectedRange: self.$userSelectedRange,
                        data: self.$data,
                        stats: self.$stats,
                        queryProgress: self.$entryFilterProgress,
                        loadingProgress: self.$loadingProgress
                    )
                    .onChange(of: self.userSelectedRange) { oldValue, newValue in
                        // When the user selects a new visible range, let's dump our caches and re-query.
                        Logger.ui.info("Visible date range changed to \(newValue)")
                        self.updateCurrentLoadingProgress()
                        self.coalescedRegenerateEntries(delay: 0, cancelPrevious: true)
                        
                        Analytics.track("Change Range", [
                            .analytics_dateRange : newValue.upperBound.timeIntervalSince(newValue.lowerBound),
                        ])
                    }
                    
                    //
                    // Selected Logs
                    //
                    SelectedLogsView(selectedEntries: self.$selectedEntries)
                }
            }
        }
        .inspector(isPresented: self.$isShowingInspector) {
            StatsInspectorView(
                data: self.$data
            )
            .inspectorColumnWidth(ideal: 204)
            .toolbar {
                Button("Stats", systemImage: "list.number.rtl") {
                    self.isShowingInspector = !self.isShowingInspector
                }
                .imageScale(.small)
            }
        }
        .onAppear {
            Logger.ui.debug("Content view appeared")
        }
        .task {
            await self.loadLogarchiveIfNecessary()
        }
    }
    
    // MARK: - Loading
    
    func loadLogarchiveIfNecessary() async {
        do {
            try await self.database.loadLogarchivesIfNecessary() { progresses in
                self.loadingProgresses = progresses
                self.ensureValidUserSelectedRange()
                self.updateCurrentLoadingProgress()
            } updatedDatabaseRange: { range in
                self.ensureValidUserSelectedRange()
                self.updateCurrentLoadingProgress()
            } chunkLoaded: { loadedRange in
                self.ensureValidUserSelectedRange()
                self.updateCurrentLoadingProgress()
                if self.userSelectedRange.overlaps(loadedRange) {
                    Task.detached(priority: .low) {
                        self.coalescedRegenerateEntries(delay: 0, cancelPrevious: false)
                    }
                }
            }
            
            self.ensureValidUserSelectedRange()
            self.coalescedRegenerateEntries(delay: 0.1, cancelPrevious: false)
        } catch {
            Logger.ui.fault("Failed to import logs: \(error)")
        }
        self.loadingProgresses = [:]
    }
    
    private func updateCurrentLoadingProgress() {
        let end = self.database.range.upperBound
        let userStart = self.userSelectedRange.lowerBound
        let userEnd = self.userSelectedRange.upperBound
        
        let matchingProgresses = self.loadingProgresses.filter {
            if let range = $0.key.knownRange(end: end) {
                return range.contains(userStart) && range.contains(userEnd)
            } else {
                return false
            }
        }
        
        let smallestDateRangeProgress = matchingProgresses.min { $0.key < $1.key }
        
        var newProgress = smallestDateRangeProgress?.value
        if let progress = newProgress, progress.fractionCompleted >= 1 {
            newProgress = nil
        }
        
        withAnimation(.otter) {
            self.loadingProgress = newProgress
        }
    }
    
    // MARK: - Regenerating Data
    
    nonisolated func coalescedRegenerateEntries(delay: TimeInterval = 0.2, cancelPrevious: Bool) {
        self.regenerateEntriesCoalescer.coalesce(delay: delay, cancelPrevious: cancelPrevious) {
            try await self.regenerateEntries()
        }
    }
    
    func coalescedRegenerateActivities(delay: TimeInterval = 0.2, cancelPrevious: Bool = true) {
        self.regenerateActivitiesCoalescer.coalesce(delay: delay, cancelPrevious: cancelPrevious) {
            try await self.regenerateActivities()
        }
    }
    
    nonisolated func regenerateEntries() async throws {
        try await self.dataRegenerationLock.withLock {
            try await self._regenerateEntries()
        }
    }
    
    nonisolated func _regenerateEntries() async throws {
        Logger.ui.debug("Will regenerate entries")
        
        // 💩 Warning 💩
        //
        //
        // Make sure the query in our filtered data is up to date.
        // We _could_ just bind the FilteredData's query to the UI, but that has some problems.
        // For example:
        // 1. User types in a query
        // 2. We start this async filter task
        // 3. User types some more
        // 4. We finish the filter and set the new filtered data.
        //
        // Step 4 will overwrite the user's new query with the old one.
        // We might be able to get around this some other way, but for now let's keep them separate.
        //
        //
        
        // We only want to show a spinner if the filtering takes a long-ish time.
        // Let's set the progress spinner after a delay. We'll cancel this later if we finish early.
        let progress = Progress()
        let progressTask = Task.detached {
            try await Task.sleep(for: .seconds(0.2))
            try await MainActor.run {
                try Task.checkCancellation()
                withAnimation(.otter) {
                    self.entryFilterProgress = progress
                }
            }
        }
        
        var data = await MainActor.run {
            var data = self.data
            data.selectedActivityIDs = self.selectedActivityIDs
            data.query = self.query.topLevelQuery
            data.userSelectedRange = self.userSelectedRange
            return data
        }
        try await data.regenerateEntries(progress: progress)
        let newData = data
        
        progressTask.cancel()
        _ = await progressTask.result
        
        await MainActor.run {
            self.data = newData
            withAnimation(.otter) {
                self.entryFilterProgress = nil
            }
            
            // After regenerating entries, we want to regenerate activities.
            // Do the entries first so that they show up very quickly.
            // The user won't mind waiting a tiny bit for activities.
            self.coalescedRegenerateActivities()
        }
    }
    
    nonisolated func regenerateActivities() async throws {
        try await self.dataRegenerationLock.withLock {
            try await self._regenerateActivities()
        }
    }
    
    nonisolated func _regenerateActivities() async throws {
        Logger.ui.debug("Will regenerate activities")
        
        // We only want to show a spinner if the filtering takes a long-ish time.
        // Let's set the progress spinner after a delay. We'll cancel this later if we finish early.
        let progress = Progress()
        let progressTask = Task.detached {
            try await Task.sleep(for: .seconds(0.4))
            try await MainActor.run {
                try Task.checkCancellation()
                withAnimation(.otter) {
                    self.activityFilterProgress = progress
                }
            }
        }
        
        var data = await MainActor.run {
            var data = self.data
            data.activityFilter = self.activityFilter
            return data
        }
        
        do {
            try data.regenerateActivities()
            let newData = data
            await MainActor.run {
                self.data = newData
                
                // Make sure the selected activities are all actually visible.
                let allActivities = newData.recursiveActivitiesByID
                self.selectedActivityIDs = self.selectedActivityIDs.filter { allActivities[$0] != nil }
            }
        } catch {
            // Nothing.
        }
        
        progressTask.cancel()
        await MainActor.run {
            withAnimation(.otter) {
                self.activityFilterProgress = nil
            }
        }
    }
    
    // MARK: - Stuff
    
    func ensureValidUserSelectedRange() {
        // If we have some sort of invalid range, default to the last five minutes.
        let selectedRange = self.userSelectedRange
        if selectedRange.lowerBound == .distantPast || selectedRange.upperBound == .distantFuture {
            let databaseRange = self.database.range
            let databaseEnd = databaseRange.upperBound
            if databaseEnd != .distantFuture {
                let fiveMinutesBefore = databaseEnd - (5 * 60)
                self.userSelectedRange = fiveMinutesBefore...databaseEnd
            }
        }
    }
    
    func modifyQueryForEntryMenuItem(_ item: EntryTableView.MenuItem) {
        // TODO: this really deserves a test...
        let property = item.property
        switch property {
        case .type:
            Logger.ui.fault("Should not try to modify query with type property")
            
        case .date:
            Logger.ui.fault("Should not try to modify query with date property")
            
        case .activity, .process, .pid, .thread, .subsystem, .category, .message:
            // Add the new query to the top-level query if necessary.
            // First, make sure the top-level query is an "and" query, not "or".
            let originalQuery = self.query.topLevelQuery
            var newQuery = (originalQuery.compoundQuery.variant == .and) ? originalQuery : .and([ originalQuery ])
            var subqueries = newQuery.compoundQuery.subqueries
            
            // First, check if we already have a subquery for this in our top level query.
            // We might just be able to change the comparison.
            let value = item.entry.stringValue(for: item.property)
            let matchingIndex = subqueries.firstIndex {
                if case let .property(existingPropertyQuery) = $0 {
                    return (existingPropertyQuery.property == property.queryProperty) && (existingPropertyQuery.value == value)
                } else {
                    return false
                }
            }
            
            if let matchingIndex {
                // The desired subquery already exists in the top level query.
                // Let's just make sure it has the right comparison type.
                subqueries[matchingIndex].propertyQuery.comparison = item.action.comparison
            } else {
                // We need to add the new subquery.
                if let queryProperty = property.queryProperty {
                    let subquery = Subquery.property(PropertyQuery(property: queryProperty, comparison: item.action.comparison, value: value))
                    subqueries.insert(subquery, at: 0)
                }
            }
            
            newQuery.compoundQuery.subqueries = subqueries
            
            withAnimation(.otter) {
                self.query.topLevelQuery = newQuery
            }
        }
    }
}

#Preview {
    ContentView(database: Database.sampleDatabase())
        .environment(SavedQueries())
        .frame(width: 900, height: 600)
}
