//
//  StatsInspectorView.swift
//  Otter
//
//  Created by Tim Mahoney on 2/8/24.
//

import SwiftUI

public struct StatsInspectorView : View {
    
    @Binding var data: FilteredData
    
    @State var expandedSections: Set<String> = []
    
    @State var progress: Progress? = nil

    static let statPadding: CGFloat = 7
    static let sidePadding: CGFloat = 16
    
    static let countForeground: any ShapeStyle = .secondary
    
    static let sectionFont: Font = .headline
    static let sectionForeground: any ShapeStyle = .primary
    static let sectionButtonPadding: CGFloat = -6
    static let sectionBottomPadding: CGFloat = 8
    
    static let subSectionFont: Font = .callout
    static let subSectionForeground: any ShapeStyle = .secondary
    static let subSectionButtonPadding: CGFloat = -5
    static let subSectionBottomPadding: CGFloat = 4
    
    @State var stats: InspectorStats = .init()
    @State var allStats: InspectorStats = .init()
    @State var filteredStats: InspectorStats = .init()
    @State var filterString: String = ""
    
    /// True if the filtered data changed. If false, we'll only re-filter our existing stats with our filter string.
    @State var needsToRegenerateAllStats = true
    
    @AppStorage("OTStatFormat") var format: Format = .global
    
    enum Format : String {
        case global
        case perProcess
    }
    
    public var body: some View {
        VStack(alignment: .center, spacing: 0) {
            
            let data = self.data
            if !data.entries.isEmpty {
                
                HStack(spacing: 8) {
                    Picker("Choose stat format", selection: self.$format) {
                        ForEach([Format.global, Format.perProcess]) { format in
                            Text(format.nameKey)
                                .tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: self.format) { oldValue, newValue in
                        Analytics.track("Changed Stat Inspector Format", [
                            .analytics_format: newValue.rawValue
                        ])
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding([.leading, .trailing], 8)
                
                TextField("Filter Stats", text: self.$filterString)
                    .padding([.leading, .trailing], 8)
                    .textFieldStyle(.roundedBorder)
                
                switch self.format {
                case .global:
                    self.globalStatsView()
                case .perProcess:
                    self.perProcessStatsView()
                }
                
                Spacer()
            } else {
                Text("No stats")
                    .opacity(0.3)
                    .font(.callout.monospaced())
            }
        }
        .onChange(of: self.data.lastRegenerateEntriesDate) {
            self.needsToRegenerateAllStats = true
            self.regenerateStats()
        }
        .onChange(of: self.filterString) {
            self.regenerateStats()
        }
        .onAppear {
            self.regenerateStats()
        }
        .toolbar {
            if self.progress != nil {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .opacity(0.5)
            }
        }
    }
    
    @ViewBuilder
    func globalStatsView() -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                //
                // Processes
                //
                self.statsSection(self.stats.processStats)
                
                if !self.stats.subsystemStats.stats.isEmpty {
                    self.sectionSeparator()
                }
                
                //
                // Subsystems
                //
                self.statsSection(self.stats.subsystemStats)
                
                if !self.stats.activityStats.stats.isEmpty {
                    self.sectionSeparator()
                }
                
                //
                // Activities
                //
                self.statsSection(self.stats.activityStats)
            }
            .padding([.leading, .trailing], Self.sidePadding)
        }
    }
    
    @ViewBuilder
    func perProcessStatsView() -> some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: [GridItem()]) {
                ForEach(self.stats.perProcessStats) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        if section.process != self.stats.perProcessStats.first?.process {
                            self.sectionSeparator()
                        }
                        
                        HStack {
                            Text(section.process)
                                .font(.headline.monospaced())
                            Spacer()
                            Text(verbatim: "\(section.count.formatted())")
                                .font(.callout.monospaced())
                                .foregroundStyle(Self.countForeground)
                        }
                        .padding(.top, 16)
                        
                        self.statsSection(section.subsystemStats)
                        self.statsSection(section.activityStats)
                    }
                }
            }
            .padding([.leading, .trailing], Self.sidePadding)
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    func statsSection(
        _ section: StatSection,
        isExpanded: Binding<Bool>? = nil
    ) -> some View {
        let isExpandedKey = section.isExpandedKey
        let isExpanded = self.expandedSections.contains(isExpandedKey)
        let totalStatCount = section.stats.count
        
        if totalStatCount > 0 {
            let statsToShow = (isExpanded || totalStatCount < section.expandLimit) ? section.stats : Array(section.stats.prefix(section.contractedCount))
            
            HStack(alignment: .top, spacing: 0) {
                
                //
                // Name (with possible show-all chevron)
                //
                if section.showSectionName {
                    let showExpandButton = totalStatCount >= section.expandLimit
                    
                    let font = section.parentSection == nil ? Self.sectionFont : Self.subSectionFont
                    let foreground = section.parentSection == nil ? Self.sectionForeground : Self.subSectionForeground
                    let buttonPadding = section.parentSection == nil ? Self.sectionButtonPadding : Self.subSectionButtonPadding
                    let bottomPadding = section.parentSection == nil ? Self.sectionBottomPadding : Self.subSectionBottomPadding
                    
                    Button {
                        withAnimation(.otter) {
                            if isExpanded {
                                self.expandedSections.remove(isExpandedKey)
                                Analytics.track("Contract Stat Section", [
                                    .analytics_statName: section.name,
                                    .analytics_format: self.format.rawValue,
                                ])
                            } else {
                                self.expandedSections.insert(isExpandedKey)
                                Analytics.track("Expand Stat Section", [
                                    .analytics_statName: section.name,
                                    .analytics_format: self.format.rawValue,
                                ])
                            }
                        }
                    } label: {
                        HStack {
                            Text(verbatim: section.name)
                                .font(font)
                                .foregroundStyle(foreground)
                            if showExpandButton {
                                Image(systemName: "chevron.right")
                                    .rotationEffect(isExpanded ? .degrees(90) : .zero)
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                                    .padding(.trailing, 1)
                            }
                        }
                    }
                    .buttonStyle(.accessoryBar)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .labelsHidden()
                    .disabled(!showExpandButton)
                    .padding(.leading, buttonPadding)
                    .padding(.bottom, bottomPadding)
                    
                    Spacer()
                    
                    Text(verbatim: "\(section.stats.count.formatted())")
                        .font(.callout.monospaced())
                        .foregroundStyle(.tertiary)
                        .baselineOffset(-2)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
            .lineLimit(1)
            
            if statsToShow.isEmpty {
                Text("None")
                    .foregroundStyle(.tertiary)
                    .font(.body.monospaced())
                    .padding(.bottom, 24)
            } else {
                VStack(alignment: .leading, spacing: Self.statPadding) {
                    
                    ForEach(statsToShow) { stat in
                        HStack(spacing: 0) {
                            let name = stat.name.isEmpty ? String(localized: "<Empty>") : stat.name
                            Text(verbatim: name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(verbatim: "\(stat.value.formatted())")
                                .font(.callout.monospaced())
                                .foregroundStyle(Self.countForeground)
                        }
                    }
                    
                    let hiddenStatCount = totalStatCount - statsToShow.count
                    if hiddenStatCount > 0 {
                        Button("\(hiddenStatCount) more…") {
                            withAnimation(.otter) {
                                if isExpanded {
                                    self.expandedSections.remove(isExpandedKey)
                                    Analytics.track("Contract Stat Section (More Button)", [
                                        .analytics_statName: section.name,
                                        .analytics_format: self.format.rawValue,
                                    ])
                                } else {
                                    self.expandedSections.insert(isExpandedKey)
                                    Analytics.track("Expand Stat Section (More Button)", [
                                        .analytics_statName: section.name,
                                        .analytics_format: self.format.rawValue,
                                    ])
                                }
                            }
                        }
                        .buttonStyle(.accessoryBar)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.leading, -5)
                    }
                }
                .font(.subheadline.monospaced())
                .lineLimit(1)
            }
        }
    }
    
    @ViewBuilder
    func sectionSeparator() -> some View {
        Rectangle()
            .fill(.tertiary.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .padding(.top, 16)
    }
    
    @State var regenerateTask: Task<Void, Error>?
    
    func regenerateStats() {
        Logger.ui.debug("Entries changed for stat inspector, regenerating data")
        
        // We only want to show a spinner if the filtering takes a long-ish time.
        // Let's set the progress spinner after a delay. We'll cancel this later if we finish early.
        let progressTask = Task.detached {
            try await Task.sleep(for: .seconds(0.25))
            try await MainActor.run {
                try Task.checkCancellation()
                withAnimation(.otter) {
                    self.progress = Progress()
                }
            }
        }
        
        self.regenerateTask?.cancel()
        
        self.regenerateTask = Task.detached {
            // Only regenerate all our stats if something actually changed.
            let data = await MainActor.run { self.data }
            var (allStats, filter, needsToRegenerateAllStats) = await MainActor.run { (self.allStats, self.filterString, self.needsToRegenerateAllStats) }
            if needsToRegenerateAllStats {
                let (entries, activitiesByID) = await MainActor.run {
                    (data.entries, data.recursiveActivitiesByID)
                }
                let (processStats, subsystemStats, activityStats, perProcessStats) = await Self.regenerateStats(entries, activitiesByID: activitiesByID)
                allStats.processStats = processStats
                allStats.subsystemStats = subsystemStats
                allStats.activityStats = activityStats
                allStats.perProcessStats = perProcessStats
            }
            
            // Always filter the stats with the filter string.
            var filteredStats = allStats
            if !filter.isEmpty {
                filteredStats.processStats.stats = allStats.processStats.stats
                    .filter { $0.name.localizedCaseInsensitiveContains(filter) }
                    .sorted { $0.value > $1.value }
                filteredStats.subsystemStats.stats = allStats.subsystemStats.stats
                    .filter { $0.name.localizedCaseInsensitiveContains(filter) }
                    .sorted { $0.value > $1.value }
                filteredStats.activityStats.stats = allStats.activityStats.stats
                    .filter { $0.name.localizedCaseInsensitiveContains(filter) }
                    .sorted { $0.value > $1.value }
                
                filteredStats.perProcessStats = allStats.perProcessStats.compactMap {
                    var filtered = $0
                    let matchesProcess = filtered.process.localizedStandardContains(filter)
                    if !matchesProcess {
                        filtered.activityStats.stats = filtered.activityStats.stats
                            .filter { $0.name.localizedCaseInsensitiveContains(filter) }
                            .sorted { $0.value > $1.value }
                        filtered.subsystemStats.stats = filtered.subsystemStats.stats
                            .filter { $0.name.localizedCaseInsensitiveContains(filter) }
                            .sorted { $0.value > $1.value }
                        var totalCount = filtered.activityStats.stats.reduce(into: 0) { $0 += $1.value }
                        totalCount += filtered.subsystemStats.stats.reduce(into: 0) { $0 += $1.value }
                        filtered.count = totalCount
                    }
                    if !filtered.subsystemStats.stats.isEmpty || !filtered.activityStats.stats.isEmpty {
                        return filtered
                    } else {
                        return nil
                    }
                }
                .sorted { $0.count > $1.count }
            }
            
            progressTask.cancel()
            try Task.checkCancellation()
            
            let newAllStats = allStats
            let newFilteredStats = filteredStats
            try await MainActor.run {
                try Task.checkCancellation()
                if self.needsToRegenerateAllStats {
                    self.allStats = newAllStats
                    self.needsToRegenerateAllStats = false
                }
                self.stats = newFilteredStats
                self.regenerateTask = nil
                Logger.ui.debug("Finished setting new data for stat inspector")
                
                withAnimation(.otter) {
                    self.progress = nil
                }
            }
        }
    }
    
    public static func regenerateStats(
        _ entries: [Entry],
        activitiesByID: [Activity.ID : Activity]
    )
    -> (processStats: StatSection, subsystemStats: StatSection, activityStats: StatSection, perProcessStats: [ProcessStatSection]) {
        
        // Go through all the entries and sum up the global and per-process stats.
        let start = Date.now
        
        // Do this in parallel because this stuff is pretty slow.
        // Accumulate the counts for each concurrent batch and sum them all up.
        let batchCount = 8
        let batchSize = Swift.max(entries.count / batchCount, 100)
        let batchStarts = stride(from: 0, to: entries.count, by: batchSize).map { $0 }
        let processCountsLock = OSAllocatedUnfairLock<[String : Int]>(initialState: [:])
        let subsystemCountsLock = OSAllocatedUnfairLock<[String : Int]>(initialState: [:])
        let activityCountsLock = OSAllocatedUnfairLock<[String : Set<os_activity_id_t>]>(initialState: [:])
        let perProcessSubsystemCountsLock = OSAllocatedUnfairLock<[String : [String : Int]]>(initialState: [:])
        let perProcessActivitiesLock = OSAllocatedUnfairLock<[String : [String : Set<os_activity_id_t>]]>(initialState: [:])
        DispatchQueue.concurrentPerform(iterations: batchStarts.count) { i in
            let batchStart = batchStarts[i]
            let batchEnd = Swift.min(batchStart + batchSize, entries.count)
            let batch = Array(entries[batchStart..<batchEnd])
            
            // Forgive the long disgusting tuple. It's faster than a for-each loop.
            let (
                processCounts,
                subsystemCounts,
                activityCounts,
                perProcessSubsystemCounts,
                perProcessActivities
            ): (
                [String : Int],
                [String : Int],
                [String : Set<os_activity_id_t>],
                [String : [String : Int]],
                [String : [String : Set<os_activity_id_t>]]
            ) = batch.reduce(into: ([:], [:], [:], [:], [:])) { result, entry in
                let process = entry.process
                result.0[process, default: 0] += 1
                
                if let subsystem = entry.subsystem {    
                    result.1[subsystem, default: 0] += 1
                    result.3[process, default: [:]][subsystem, default: 0] += 1
                }
                if entry.activityIdentifier != 0, let activity = activitiesByID[entry.activityIdentifier] {
                    result.2[activity.name, default: .init()].insert(activity.id)
                    result.4[process, default: [:]][activity.name, default: .init()].insert(activity.id)
                }
            }
            
            processCountsLock.withLock { $0.merge(processCounts) { $0 + $1 } }
            subsystemCountsLock.withLock { $0.merge(subsystemCounts) { $0 + $1 } }
            activityCountsLock.withLock { $0.merge(activityCounts) { $0.union($1) } }
            perProcessSubsystemCountsLock.withLock {
                $0.merge(perProcessSubsystemCounts) { lhs, rhs in
                    lhs.merging(rhs) { $0 + $1 }
                }
            }
            perProcessActivitiesLock.withLock {
                $0.merge(perProcessActivities) { lhs, rhs in
                    lhs.merging(rhs) { $0.union($1) }
                }
            }
        }
        
        let processCounts = processCountsLock.currentState
        let sortedProcessCounts = processCounts.sorted { $0.value > $1.value }
        let processStats = sortedProcessCounts.map { Stat(name: $0.key, value: $0.value) }
        let processSection = StatSection(name: .otter_processes, stats: processStats, expandLimit: InspectorStats.statCountExpandLimitGlobal, contractedCount: InspectorStats.statCountContractedGlobal)
        
        let globalSubsystemCounts = subsystemCountsLock.currentState
        let sortedSubsystemCounts = globalSubsystemCounts.sorted { $0.value > $1.value }
        let subsystemStats = sortedSubsystemCounts.map { Stat(name: $0.key, value: $0.value) }
        let subsystemSection = StatSection(name: .otter_subsystems, stats: subsystemStats, expandLimit: InspectorStats.statCountExpandLimitGlobal, contractedCount: InspectorStats.statCountContractedGlobal)
        
        let globalActivityCounts = activityCountsLock.currentState.mapValues { $0.count }
        let sortedActivityCounts = globalActivityCounts.sorted { $0.value > $1.value }
        let activityStats = sortedActivityCounts.map { Stat(name: $0.key, value: $0.value) }
        let activitySection = StatSection(name: .otter_activities, stats: activityStats, expandLimit: InspectorStats.statCountExpandLimitGlobal, contractedCount: InspectorStats.statCountContractedGlobal)
        
        // If there's only one subsystem in this set of logs, then we don't need to show it in the per-process stats.
        let showPerProcessSubsystems = (subsystemStats.count > 1)
        
        let perProcessSubsystemCounts = perProcessSubsystemCountsLock.currentState
        let perProcessActivityCounts = perProcessActivitiesLock.currentState
        let perProcessSections = sortedProcessCounts.map { processCount in
            let processSubsystems = perProcessSubsystemCounts[processCount.key, default: [:]].sorted { $0.value > $1.value }
            let subsystemStats = showPerProcessSubsystems ? processSubsystems.map { Stat(name: $0.key, value: $0.value) } : []
            let processActivities = perProcessActivityCounts[processCount.key, default: [:]].sorted { $0.value.count > $1.value.count }
            let activityStats = processActivities.map { Stat(name: $0.key, value: $0.value.count) }
            
            let perProcessSubsystemSection = StatSection(name: .otter_subsystems, parentSection: processCount.key, stats: subsystemStats, expandLimit: InspectorStats.statCountExpandLimitPerProcess, contractedCount: InspectorStats.statCountContractedPerProcess)
            let perProcessActivitySection = StatSection(name: .otter_activities, parentSection: processCount.key, stats: activityStats, expandLimit: InspectorStats.statCountExpandLimitPerProcess, contractedCount: InspectorStats.statCountContractedPerProcess)
            return ProcessStatSection(process: processCount.key, count: processCount.value, subsystemStats: perProcessSubsystemSection, activityStats: perProcessActivitySection)
        }
        
        Logger.ui.debug("Regenerating stats took \(start.secondsSinceNowString) for \(entries.count.formatted()) entries")
        
        return (processSection, subsystemSection, activitySection, perProcessSections)
    }
}

extension StatsInspectorView.Format : Identifiable {
    
    var id: String { self.rawValue }
    
    var nameKey: LocalizedStringKey {
        switch self {
        case .global: return "Global"
        case .perProcess : return "Processes"
        }
    }
}

extension String {
    
    static let otter_processes = String(localized: "Processes")
    static let otter_subsystems = String(localized: "Subsystems")
    static let otter_activities = String(localized: "Activities")
}

#Preview {
    PreviewBindingHelper(FilteredData.previewData()) { data in
        StatsInspectorView(data: data)
            .frame(width: 300, height: 700)
    }
}
