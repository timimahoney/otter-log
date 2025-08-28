//
//  StatsTests.swift
//  OtterTests
//
//  Created by Tim Mahoney on 3/7/24.
//

import XCTest
import Otter

final class StatsTests: XCTestCase {
    
    func testGenerateStats_iOSSysdiagnose() async throws {
        let fileURL = try self.sampleiOSSysdiagnoseLogarchiveFileURL        
        try await self.testGenerateStats(fileURL)
    }
    
    func testGenerateStats_Million() async throws {
        let fileURL = try self.sampleMillionLogarchiveFileURL
        try await self.testGenerateStats(fileURL)
    }
    
    func testGenerateStats_Small() async throws {
        let fileURL = try self.sampleSmallLogarchiveFileURL
        try await self.testGenerateStats(fileURL)
    }
    
    func testGenerateStats(_ url: URL) async throws {
        let database = try await self.newDatabase(url)
        var data = FilteredData(database)
        try await data.regenerateEntries()
        try data.regenerateActivities()
        let stats = StatsInspectorView.regenerateStats(data.entries, activitiesByID: data.recursiveActivitiesByID)
        
        let uniqueProcesses = data.entries.reduce(into: Set<String>()) { $0.insert($1.process) }
        XCTAssertEqual(stats.perProcessStats.count, uniqueProcesses.count)
        XCTAssertEqual(stats.processStats.stats.count, uniqueProcesses.count)
        
        let activityCounts = data.recursiveActivitiesByID.reduce(into: [String : Int]()) { $0[$1.value.name, default: 0] += 1 }
        XCTAssertEqual(stats.activityStats.stats.count, activityCounts.count)
        for activityStat in stats.activityStats.stats {
            XCTAssertEqual(activityStat.value, activityCounts[activityStat.name, default: 0])
        }
    }
}
