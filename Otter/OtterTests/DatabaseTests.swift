//
//  DatabaseTests.swift
//  OtterTests
//
//  Created by Tim Mahoney on 1/8/24.
//

import os.activity
import Otter
import XCTest

final class DatabaseTests: XCTestCase {
    
    func testLoadSampleData_Small() async throws {
        try await _testLoadSampleData_Small(slow: false)
    }
    
    func testLoadSampleData_Small_Slow() async throws {
        try await _testLoadSampleData_Small(slow: true)
    }
    
    func _testLoadSampleData_Small(slow: Bool) async throws {
        let fileURL = try self.sampleSmallLogarchiveFileURL
        try await self.testLoadSampleData(fileURL, slow: slow, entries: 261_810, activities: 3_347)
    }
    
    func testLoadSampleData_Million() async throws {
        try await _testLoadSampleData_Million(slow: false)
    }
    
    func testLoadSampleData_Million_Slow() async throws {
        try await _testLoadSampleData_Million(slow: true)
    }
    
    func _testLoadSampleData_Million(slow: Bool) async throws {
        let fileURL = try self.sampleMillionLogarchiveFileURL
        try await self.testLoadSampleData(fileURL, slow: slow, entries: 1_001_139, activities: 132_292)
    }
    
    func testLoadSampleData_iOSSysdiagnose() async throws {
        try await self._testLoadSampleData_iOSSysdiagnose(slow: false)
    }
    
    func testLoadSampleData_iOSSysdiagnose_Slow() async throws {
        try XCTSkipIf(true, "This is too slow to run all the time.")
        try await self._testLoadSampleData_iOSSysdiagnose(slow: true)
    }
    
    func _testLoadSampleData_iOSSysdiagnose(slow: Bool) async throws {
        let fileURL = try self.sampleiOSSysdiagnoseLogarchiveFileURL
        try await self.testLoadSampleData(fileURL, slow: slow, entries: 6_291_656, activities: 360_965)
    }
    
    func testLoadSampleData(
        _ fileURL: URL,
        slow: Bool,
        entries expectedEntryCount: Int,
        activities expectedActivityCount: Int
    ) async throws {
        let database = self.newDatabase()
        
        database.addLogarchive(fileURL)
        try await database.loadLogarchivesIfNecessary(slow: slow)
        
        // Check to make sure we got what we expected.
        // Some magic numbers for a known log archive.
        let entries = database.entries
        XCTAssertEqual(entries.count, expectedEntryCount)
        
        // Make sure we have the proper count of activities.
        let activities = entries.filter { $0.type == .activity }
        XCTAssertEqual(activities.count, expectedActivityCount)
        
        // Make sure it's sorted.
        let entryDates = entries.map(\.date)
        let sortedEntryDates = entryDates.sorted()
        XCTAssert(entryDates == sortedEntryDates, "Entries were not sorted")
    }
    
    func testQueries_Million() async throws {
        let fileURL = try self.sampleMillionLogarchiveFileURL
        let database = try await self.newDatabase(fileURL)
        
        // Check to make sure we got what we expected.
        // Some magic numbers for a known log archive.
        let entryCount = database.entries.count
        XCTAssertEqual(entryCount, 1_001_139)
        
        try await self.testQuery(
            query: .and([
                .or([
                ]),
                .or([
                    .or([])
                ]),
            ]),
            expected: entryCount,
            database: database
        )
        
        try await self.testQuery(
            query: .and([
                .or([
                ]),
                .or([
                    .or([])
                ]),
                .equals(.subsystem, "com.apple.cloudkit"),
            ]),
            expected: 3753,
            database: database
        )
        
        try await self.testQuery(
            query: .contains(.subsystem, "cloudkit"),
            expected: 3754,
            database: database
        )
        try await self.testQuery(
            query: .equals(.subsystem, "com.apple.cloudkit"),
            expected: 3753,
            database: database
        )
        try await self.testQuery(
            query: .contains(.message, "cloud"),
            expected: 11448,
            database: database
        )
        
        // Let's see if there are differences when a query is ordered differently.
        try await self.testQuery(
            query: .and([
                .equals(.subsystem, "com.apple.cloudkit"),
                .or([
                    .contains(.message, "Starting operation"),
                    .contains(.message, "Finished operation"),
                ])
            ]),
            expected: 293,
            database: database
        )
        
        try await self.testQuery(
            query: .and([
                .or([
                    .contains(.message, "Starting operation"),
                    .contains(.message, "Finished operation"),
                ]),
                .equals(.subsystem, "com.apple.cloudkit"),
            ]),
            expected: 293,
            database: database
        )
    }
    
    // MARK: - Queries
    
    struct QueryTest {
        let name: String
        let query: Subquery
        let expected: Bool
    }
    
    func testQueries_Fundamentals() async throws {
        let database = self.newDatabase()
        
        // In order to make testing all the properties easier, let's use the same string for each property.
        let stringValue = "I am Otter, hear me roar."
        
        // Add a new entry. We'll perform queries against this entry to make sure everything works as expected.
        let entry = Entry(
            type: .log,
            date: Date.now,
            message: stringValue,
            activityIdentifier: 2,
            process: stringValue,
            processIdentifier: 123,
            sender: stringValue,
            threadIdentifier: 321,
            level: .info,
            subsystem: stringValue,
            category: stringValue
        )
        database.add([entry])
        
        //
        // Empty compound queries.
        //
        
        try await self.testQuery(
            name: "Empty and",
            query: .and([]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "Empty or",
            query: .and([]),
            expected: 1,
            database: database
        )
        
        //
        // All comparisons for each property.
        //
        for property in PropertyQuery.Property.allCases {
            switch property {
            case .message, .subsystem, .category, .process, .sender:
                try await self.testQuery(
                    name: "\(property) contains (true)",
                    query: .contains(property, "hear me roar"),
                    expected: 1,
                    database: database
                )
                try await self.testQuery(
                    name: "\(property) contains (false)",
                    query: .contains(property, "hear me poo"),
                    expected: 0,
                    database: database
                )
                try await self.testQuery(
                    name: "\(property) equals (true)",
                    query: .equals(property, stringValue),
                    expected: 1,
                    database: database
                )
                try await self.testQuery(
                    name: "\(property) equals (false)",
                    query: .equals(property, "I am not Otter"),
                    expected: 0,
                    database: database
                )
                try await self.testQuery(
                    name: "\(property) does not contain (true)",
                    query: .doesNotContain(property, "Beaver"),
                    expected: 1,
                    database: database
                )
                try await self.testQuery(
                    name: "\(property) does not contain (false)",
                    query: .doesNotContain(property, "Otter"),
                    expected: 0,
                    database: database
                )
                
                //
                // Case insensitivity
                //
                try await self.testQuery(
                    name: "Case insensitivity (contains)",
                    query: .contains(property, "hear me ROAR"),
                    expected: 1,
                    database: database
                )
                try await self.testQuery(
                    name: "Case insensitivity (equals, uppercased)",
                    query: .equals(property, stringValue.uppercased()),
                    expected: 0,
                    database: database
                )
                try await self.testQuery(
                    name: "Case insensitivity (equals, lowercased)",
                    query: .equals(property, stringValue.lowercased()),
                    expected: 0,
                    database: database
                )
                try await self.testQuery(
                    name: "Case insensitivity (doesn't equal)",
                    query: .doesNotEqual(property, stringValue.uppercased()),
                    expected: 1,
                    database: database
                )
                try await self.testQuery(
                    name: "Case insensitivity (doesn't contain)",
                    query: .doesNotContain(property, "ROAR"),
                    expected: 0,
                    database: database
                )
                
                //
                // Empty property queries.
                //
                for comparison in PropertyQuery.Comparison.allCases {
                    try await self.testQuery(
                        name: "Empty \(comparison)",
                        query: Subquery.property(PropertyQuery(property: property, comparison: comparison, value: "")),
                        expected: 1,
                        database: database
                    )
                }
                
            case .pid, .activity, .thread:
                // TODO: non-string values
                break
            }
        }
        
        //
        // Compound queries with property subquery.
        //
        try await self.testQuery(
            name: "And + property (true)",
            query: .and([ .equals(.message, stringValue) ]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "And + property (false)",
            query: .and([ .doesNotEqual(.message, stringValue) ]),
            expected: 0,
            database: database
        )
        try await self.testQuery(
            name: "Or + property (true)",
            query: .or([ .equals(.message, stringValue) ]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "Or + property (false)",
            query: .or([ .doesNotEqual(.message, stringValue) ]),
            expected: 0,
            database: database
        )
        
        //
        // Compound queries with multiple subqueries.
        //
        try await self.testQuery(
            name: "And (all true)",
            query: .and([ .equals(.message, stringValue), .equals(.category, stringValue) ]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "And (one false)",
            query: .and([ .equals(.message, stringValue), .equals(.category, "Sup") ]),
            expected: 0,
            database: database
        )
        try await self.testQuery(
            name: "And (all false)",
            query: .and([ .equals(.message, "Boop"), .equals(.category, "Sup") ]),
            expected: 0,
            database: database
        )
        try await self.testQuery(
            name: "Or (all true)",
            query: .or([ .equals(.message, stringValue), .equals(.category, stringValue) ]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "Or (one false)",
            query: .or([ .equals(.message, stringValue), .equals(.category, "Sup") ]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "Or (all false)",
            query: .or([ .equals(.message, "Boop"), .equals(.category, "Sup") ]),
            expected: 0,
            database: database
        )
        
        //
        // Complex compound queries
        //
        try await self.testQuery(
            name: "And + Or (all true)",
            query: .and([
                .equals(.message, stringValue),
                .or([ .equals(.category, stringValue), .equals(.subsystem, stringValue) ])
            ]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "And + And + Or (all true)",
            query: .and([
                .equals(.message, stringValue),
                .and([ .contains(.message, "Otter"), .contains(.category, "roar") ]),
                .or([ .equals(.category, stringValue), .equals(.subsystem, stringValue) ])
            ]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "And + And + Or (one false)",
            query: .and([
                .equals(.message, stringValue),
                .and([ .contains(.message, "Beaver"), .contains(.category, "roar") ]),
                .or([ .equals(.category, stringValue), .equals(.subsystem, stringValue) ])
            ]),
            expected: 0,
            database: database
        )
        try await self.testQuery(
            name: "Or + And + Or (all true)",
            query: .or([
                .equals(.message, stringValue),
                .and([ .contains(.message, "Otter"), .contains(.category, "roar") ]),
                .or([ .equals(.category, stringValue), .equals(.subsystem, stringValue) ])
            ]),
            expected: 1,
            database: database
        )
        try await self.testQuery(
            name: "Or + And + Or (all false)",
            query: .or([
                .equals(.message, "Yeah that's not it"),
                .and([ .contains(.message, "Beaver"), .contains(.category, "roar") ]),
                .or([ .equals(.category, "Daisies"), .equals(.subsystem, "beep boop") ])
            ]),
            expected: 0,
            database: database
        )
        
        // TODO: Entry type (correct/incorrect)
        // TODO: Log level (correct/incorrect)
        //
        // TODO: Dates (earlier/later)
        // TODO: Search for properties that are nil
    }
    
    func testQuery(name: String = "", query: Subquery, expected: Int, database: Database) async throws {
        let entries = database.entries
        let matches = try await Database.filterEntries(entries, matching: query)
        let sortedByDate = matches.sorted { $0.date < $1.date }
        XCTAssertEqual(matches, sortedByDate)
        
//        let start = Date.now
//        let context = FilterContext()
//        let normalFilter = entries.filter { query.evaluate($0, context) }
//        XCTAssertEqual(matches.count, normalFilter.count)
//        print("Normal filter took \(String(format: "%.2fs", -start.timeIntervalSinceNow))")
        
        let numberOfMatches = matches.count
        XCTAssertEqual(numberOfMatches, expected, "Wrong number of matches for test (\(name)) query=\(query)")
    }
    
    /// Make sure the configurations accessor returns the correct values.
    func testConfiguration() throws {
        try XCTSkipIf(true, "TODO: Make sure the configurations accessor returns the correct values")
        XCTFail("Make sure the configurations accessor returns the correct values")
    }
    
    func testLoadArchivesIfNecessary() throws {
        try XCTSkipIf(true, "TODO: Make sure we load any un-loaded archives if necessary.")
        XCTFail("Make sure we load any un-loaded archives if necessary.")
    }
    
    func testFilterActivities() throws {
        try XCTSkipIf(true, "TODO: Need to test filterActivities")
        XCTFail("Need to test filterActivities")
    }
    
    func testDeleteFileAfterLoading() async throws {
        try XCTSkipIf(true, "TODO: Need to test this")
        XCTFail("Make sure we delete the file after loading if it's in the temp directory")
    }
}
