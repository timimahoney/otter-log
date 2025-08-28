//
//  SavedQueriesTests.swift
//  OtterTests
//
//  Created by Tim Mahoney on 1/13/24.
//

import XCTest
import Otter

final class SavedQueriesTests: XCTestCase {

    func testSaveQuery() throws {
        let savedQueries = self.newSavedQueries()
        XCTAssertEqual(savedQueries.savedQueries, [])
        
        let query = UserQuery(name: "One")
        savedQueries.save(query)
        XCTAssertEqual(savedQueries.savedQueries, [query])
        
        let secondQuery = UserQuery(name: "Two", topLevelQuery: .and([]))
        savedQueries.save(secondQuery)
        XCTAssertEqual(savedQueries.savedQueries, [query, secondQuery])
        
        let thirdQuery = UserQuery(name: "Three", topLevelQuery: .or([ .contains(.subsystem, ""), .contains(.subsystem, "yeah") ]))
        savedQueries.save(thirdQuery)
        XCTAssertEqual(savedQueries.savedQueries, [query, secondQuery, thirdQuery])
    }
    
    func testQueryNamed() throws {
        let savedQueries = self.newSavedQueries()
        
        let queryA = UserQuery(name: "A")
        let queryB = UserQuery(name: "B")
        let queryC = UserQuery(name: "C")
        
        XCTAssertNil(savedQueries.queryNamed("A"))
        XCTAssertNil(savedQueries.queryNamed("B"))
        XCTAssertNil(savedQueries.queryNamed("C"))
        
        savedQueries.save(queryA)
        XCTAssertEqual(savedQueries.queryNamed("A"), queryA)
        XCTAssertNil(savedQueries.queryNamed("B"))
        XCTAssertNil(savedQueries.queryNamed("C"))
        
        savedQueries.save(queryB)
        XCTAssertEqual(savedQueries.queryNamed("A"), queryA)
        XCTAssertEqual(savedQueries.queryNamed("B"), queryB)
        XCTAssertNil(savedQueries.queryNamed("C"))
        
        savedQueries.save(queryC)
        XCTAssertEqual(savedQueries.queryNamed("A"), queryA)
        XCTAssertEqual(savedQueries.queryNamed("B"), queryB)
        XCTAssertEqual(savedQueries.queryNamed("C"), queryC)
    }
    
    func testQueryMatching() throws {
        let savedQueries = self.newSavedQueries()
        
        let queryA = UserQuery(name: "A")
        let queryB = UserQuery(name: "B", topLevelQuery: .and([]))
        let queryC = UserQuery(name: "C", topLevelQuery: .and([ .contains(.subsystem, "") ]))
        
        XCTAssertNil(savedQueries.queryMatching(queryA))
        XCTAssertNil(savedQueries.queryMatching(queryB))
        XCTAssertNil(savedQueries.queryMatching(queryC))
        
        savedQueries.save(queryA)
        savedQueries.save(queryB)
        savedQueries.save(queryC)
        
        // Exact matches.
        XCTAssertEqual(savedQueries.queryMatching(queryA), queryA)
        XCTAssertEqual(savedQueries.queryMatching(queryB), queryB)
        XCTAssertEqual(savedQueries.queryMatching(queryC), queryC)
        
        // Same query, different name.
        var queryA2 = queryA
        queryA2.name = "A2"
        var queryB2 = queryB
        queryB2.name = "B2"
        var queryC2 = queryC
        queryC2.name = "C2"
        XCTAssertEqual(savedQueries.queryMatching(queryA2), queryA)
        XCTAssertEqual(savedQueries.queryMatching(queryB2), queryB)
        XCTAssertEqual(savedQueries.queryMatching(queryC2), queryC)
        
        // Same query, different ID.
        var queryA3 = queryA
        queryA3.id = 1
        var queryB3 = queryB
        queryB3.id = 2
        var queryC3 = queryC
        queryC3.id = 3
        XCTAssertEqual(savedQueries.queryMatching(queryA3), queryA)
        XCTAssertEqual(savedQueries.queryMatching(queryB3), queryB)
        XCTAssertEqual(savedQueries.queryMatching(queryC3), queryC)
        
        // Same query, different ID and name.
        var queryA4 = queryA
        queryA4.id = 1
        queryA4.name = "A4"
        var queryB4 = queryB
        queryB4.id = 2
        queryB4.name = "B4"
        var queryC4 = queryC
        queryC4.id = 3
        queryC4.name = "C4"
        XCTAssertEqual(savedQueries.queryMatching(queryA4), queryA)
        XCTAssertEqual(savedQueries.queryMatching(queryB4), queryB)
        XCTAssertEqual(savedQueries.queryMatching(queryC4), queryC)
    }
    
    func testPersistence() {
        let suiteName = UUID().uuidString
        let savedQueries = self.newSavedQueries(suiteName: suiteName)
        XCTAssertEqual(savedQueries.savedQueries, [])
        
        let query = UserQuery(name: "One")
        savedQueries.save(query)
        let secondQuery = UserQuery(name: "Two", topLevelQuery: .and([]))
        savedQueries.save(secondQuery)
        let thirdQuery = UserQuery(name: "Three", topLevelQuery: .or([ .contains(.subsystem, ""), .contains(.subsystem, "yeah") ]))
        savedQueries.save(thirdQuery)
        
        let savedQueriesB = self.newSavedQueries(suiteName: suiteName)
        XCTAssertEqual(savedQueriesB.savedQueries, savedQueries.savedQueries)
    }
    
    // MARK: - Helpers
    
    func newSavedQueries(suiteName: String = UUID().uuidString) -> SavedQueries {
        let defaults = UserDefaults.init(suiteName: "com.jollycode.otter.test.\(suiteName)")!
        return SavedQueries(defaults: defaults, defaultQueries: [])
    }
}
