//
//  FilteredDataTests.swift
//  OtterTests
//
//  Created by Tim Mahoney on 2/6/24.
//

import Otter
import XCTest

final class FilteredDataTests: XCTestCase {
    
    func testInvalidateCaches() throws {
        try XCTSkipIf(true, "TODO: Make sure we invalidate our caches at the proper times")
        XCTFail("Make sure we invalidate our caches at the proper times")
    }
    
    func testRegenerateEntries() async throws {
        let database = try await self.newDatabase(self.sampleMillionLogarchiveFileURL)
        try await self.testRegenerateEntries(database)
    }
    
    func testRegenerateEntries_LotsOfData() async throws {
        let database = try await self.newDatabase(self.sampleiOSSysdiagnoseLogarchiveFileURL)
        try await self.testRegenerateEntries(database)
    }
    
    func testRegenerateEntries(_ database: Database) async throws {
        var filteredData = FilteredData(database)
        XCTAssertGreaterThan(database.entries.count, 1)
        let range = database.range
        filteredData.userSelectedRange = range
        
        // Everything
        filteredData.query = nil
        try await filteredData.regenerateEntries()
        XCTAssertEqual(filteredData.entries, database.entries)
        
        // Only a subsystem
        filteredData.query = .contains(.subsystem, "cloudkit")
        try await filteredData.regenerateEntries()
        XCTAssertGreaterThan(filteredData.entries.count, 1)
        XCTAssertNotEqual(filteredData.entries, database.entries)
        XCTAssert(filteredData.entries.allSatisfy { $0.subsystem?.localizedCaseInsensitiveContains("cloudkit") ?? false })
        
        // Date range
        filteredData.query = nil
        let smallRange = database.range.lowerBound...(database.range.lowerBound + 60)
        filteredData.userSelectedRange = smallRange
        try await filteredData.regenerateEntries()
        XCTAssertGreaterThan(filteredData.entries.count, 1)
        XCTAssertLessThan(filteredData.entries.count, database.entries.count)
        XCTAssertNotEqual(filteredData.entries, database.entries)
        XCTAssert(filteredData.entries.allSatisfy { smallRange.contains($0.date) })
    }
    
    func testRegenerateActivities() throws {
        try XCTSkipIf(true, "TODO: Test this. Numbers are in DatabaseTests")
        XCTFail("Test this. Numbers are in DatabaseTests")
    }
    
    func testParseActivities() async throws {
        let fileURL = try self.sampleSmallLogarchiveFileURL
        let database = try await self.newDatabase(fileURL)
        var filteredData = FilteredData(database)
        
        // There are some magic numbers in here because we know what this sample database contains.
        filteredData.userSelectedRange = .distantRange
        try await filteredData.regenerateEntries()
        try filteredData.regenerateActivities()
        let activities = filteredData.activities
        let allActivities: [Activity] = activities.reduce(into: []) {
            $0.append($1)
            $0.append(contentsOf: $1.recursiveSubactivities)
        }
        let activitiesByID = allActivities.reduce(into: [Activity.ID : Activity]()) { $0[$1.id] = $1 }
        try await OTAssertEqual(allActivities.count, 3347)
        
        // We have a sync engine fetch changes activity that should have some children.
        let engineActivityID: os_activity_id_t = 72417469
        let subscriptionActivityID: os_activity_id_t = 72417977
        let fetchUserActivityID: os_activity_id_t = 72417470
        let fetchOpActivityID: os_activity_id_t = 72418030
        let engineActivity = try XCTUnwrap(activitiesByID[engineActivityID])
        let fetchUserActivity = try XCTUnwrap(activitiesByID[fetchUserActivityID])
        XCTAssertEqual(fetchUserActivity.parentID, engineActivityID)
        let subscriptionActivity = try XCTUnwrap(activitiesByID[subscriptionActivityID])
        XCTAssertEqual(subscriptionActivity.parentID, engineActivityID)
        let fetchOpActivity = try XCTUnwrap(activitiesByID[fetchOpActivityID])
        XCTAssertEqual(fetchOpActivity.parentID, engineActivityID)
        XCTAssertEqual(engineActivity.subactivityIDs, [fetchUserActivityID, subscriptionActivityID, fetchOpActivityID])
        let recursiveSubactivities = engineActivity.recursiveSubactivityIDs
        XCTAssertEqual(recursiveSubactivities.count, 105)
        XCTAssertEqual(recursiveSubactivities, [72417470, 72417597, 72417851, 72417852, 72417853, 72417905, 72417977, 72417990, 72417992, 72418068, 72418069, 72418070, 72417908, 72418081, 72418152, 72418156, 72418157, 72417893, 72417894, 72418017, 72418297, 72418298, 72418300, 72418301, 72418303, 72417916, 72418323, 72418324, 72418325, 72418326, 72417899, 72417900, 72418021, 72418022, 72418331, 72418332, 72418333, 72418334, 72418335, 72417918, 72418384, 72418385, 72418386, 72418387, 72417903, 72418416, 72418029, 72418018, 72418030, 72418397, 72418398, 72419126, 72419127, 72419128, 72419129, 72419130, 72419131, 72419204, 72419209, 72419210, 72419211, 72419212, 72418438, 72419225, 72419226, 72419227, 72419228, 72418431, 72419232, 72419132, 72419133, 72419134, 72419135, 72419200, 72419201, 72419202, 72419203, 72419205, 72419206, 72419207, 72419208, 72419213, 72419214, 72419215, 72419216, 72419217, 72419218, 72419219, 72419220, 72419221, 72419222, 72419223, 72419224, 72418399, 72418480, 72418481, 72418482, 72418432, 72418483, 72418484, 72418485, 72418486, 72418419, 72418420, 72418909])
        
        // Let's also test out the schedule sync activity.
        let scheduleActivityID: Activity.ID = 72417599
        let submitActivityID: Activity.ID = 72417968
        let scheduleActivity = try XCTUnwrap(activitiesByID[scheduleActivityID])
        XCTAssertEqual(scheduleActivity.subactivityIDs, [submitActivityID])
        let submitActivity = try XCTUnwrap(activitiesByID[submitActivityID])
        XCTAssertEqual(submitActivity.subactivityIDs, [])
        let scheduleRecursiveSubactivities = scheduleActivity.recursiveSubactivityIDs
        XCTAssertEqual(scheduleRecursiveSubactivities.count, 1)
        XCTAssertEqual(scheduleRecursiveSubactivities, [72417968])
        
        let fetchRecordChangesActivities = allActivities.filter { $0.name == "client/fetch-record-changes" }
        XCTAssertEqual(fetchRecordChangesActivities.count, 2)
        
        let engineFetchActivities = allActivities.filter { $0.name == "engine/fetch-changes" }
        XCTAssertEqual(engineFetchActivities.count, 8)
        
        // Now let's make sure each activity has a fully-formed list of subactivities.
        // We also want to make sure we don't return any child activities at the top level.
        let topLevelActivityIDs = Set(activities.map { $0.id })
        for activity in activities {
            try self.recursiveTestSubactivities(activity, topLevelActivityIDs: topLevelActivityIDs)
        }
    }
    
    func recursiveTestSubactivities(_ activity: Activity, topLevelActivityIDs: Set<Activity.ID>) throws {
        if activity.subactivityIDs.isEmpty {
            XCTAssertNil(activity.subactivities)
        } else {
            let subactivities = try XCTUnwrap(activity.subactivities)
            XCTAssertEqual(subactivities.count, activity.subactivityIDs.count)
            let subactivityIDsFromSubactivities = subactivities.map { $0.id }
            XCTAssertEqual(subactivityIDsFromSubactivities, activity.subactivityIDs)
            for subactivity in subactivities {
                XCTAssertFalse(topLevelActivityIDs.contains(subactivity.id))
                try self.recursiveTestSubactivities(subactivity, topLevelActivityIDs: topLevelActivityIDs)
            }
        }
    }
}
