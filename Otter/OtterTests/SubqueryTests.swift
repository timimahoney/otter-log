//
//  SubqueryTests.swift
//  OtterTests
//
//  Created by Tim Mahoney on 2/28/24.
//

import Foundation
import Otter
import XCTest

final class SubqueryTests: XCTestCase {
    
    // MARK: - Helpers
    
    func testRecursiveQueries() {
        var query: Subquery = .contains(.message)
        XCTAssertEqual(query.recursiveQueries, [query])
        
        query = .contains(.message, "beep")
        XCTAssertEqual(query.recursiveQueries, [query])
        
        // Single properties
        query = .equals(.message, "beep")
        XCTAssertEqual(query.recursiveQueries, [query])
        query = .equals(.subsystem)
        XCTAssertEqual(query.recursiveQueries, [query])
        query = .doesNotEqual(.category, "yay")
        XCTAssertEqual(query.recursiveQueries, [query])
        query = .doesNotContain(.process)
        XCTAssertEqual(query.recursiveQueries, [query])
        
        // Level
        query = .logLevel([.debug])
        XCTAssertEqual(query.recursiveQueries, [query])
        query = .logLevel([.debug, .info, .notice, .error, .fault])
        XCTAssertEqual(query.recursiveQueries, [query])
        
        // Compound
        query = .and([ .equals(.message), .contains(.subsystem) ])
        var subqueries = query.unsafeSubqueries
        var expected = [query, subqueries.first!, subqueries.last!]
        XCTAssertEqual(query.recursiveQueries, expected)
        
        query = .or([ .contains(.pid), .doesNotEqual(.thread) ])
        subqueries = query.unsafeSubqueries
        expected = [query, subqueries.first!, subqueries.last!]
        XCTAssertEqual(query.recursiveQueries, expected)
        
        query = .or([ 
            .or([ .contains(.pid), .doesNotEqual(.thread) ]),
            .and([ .contains(.activity), .doesNotContain(.thread) ])
        ])
        subqueries = query.unsafeSubqueries
        expected = [query, subqueries.first!, subqueries.first!.unsafeSubqueries.first!, subqueries.first!.unsafeSubqueries.last!, subqueries.last!, subqueries.last!.unsafeSubqueries.first!, subqueries.last!.unsafeSubqueries.last!]
        XCTAssertEqual(query.recursiveQueries, expected)
    }
    
    // MARK: - Analytics
    
    func testAnalyticsString() {
        var query: Subquery = .contains(.message)
        XCTAssertEqual(query.analyticsStructure, "(message ~=)")
        
        query = .contains(.message, "beep")
        XCTAssertEqual(query.analyticsStructure, "(message ~=)")
        
        query = .equals(.message, "beep")
        XCTAssertEqual(query.analyticsStructure, "(message ==)")
        
        query = .equals(.subsystem)
        XCTAssertEqual(query.analyticsStructure, "(subsystem ==)")
        
        query = .doesNotEqual(.category, "yay")
        XCTAssertEqual(query.analyticsStructure, "(category !=)")
        
        query = .doesNotContain(.process)
        XCTAssertEqual(query.analyticsStructure, "(process !~)")
        
        query = .logLevel([.debug])
        XCTAssertEqual(query.analyticsStructure, "(level in debug)")
        
        query = .logLevel([.info])
        XCTAssertEqual(query.analyticsStructure, "(level in info)")
        
        // Twice to ensure consistency
        query = .logLevel([.debug, .info, .notice, .error, .fault])
        XCTAssertEqual(query.analyticsStructure, "(level in debug|info|log|error|fault)")
        query = .logLevel([.debug, .info, .notice, .error, .fault])
        XCTAssertEqual(query.analyticsStructure, "(level in debug|info|log|error|fault)")
        
        // Twice to ensure consistency
        query = .logLevel([.debug, .notice, .fault])
        XCTAssertEqual(query.analyticsStructure, "(level in debug|log|fault)")
        query = .logLevel([.debug, .notice, .fault])
        XCTAssertEqual(query.analyticsStructure, "(level in debug|log|fault)")
        
        query = .and([ .equals(.message), .contains(.subsystem) ])
        XCTAssertEqual(query.analyticsStructure, "((message ==) && (subsystem ~=))")
        
        query = .or([ .contains(.pid), .doesNotEqual(.thread) ])
        XCTAssertEqual(query.analyticsStructure, "((pid ~=) || (thread !=))")
        
        query = .or([
            .or([ .contains(.pid), .doesNotEqual(.thread) ]),
            .and([ .contains(.activity), .doesNotContain(.thread) ])
        ])
        XCTAssertEqual(query.analyticsStructure, "(((pid ~=) || (thread !=)) || ((activity ~=) && (thread !~)))")
    }
}

extension Subquery {
    
    var unsafeSubqueries: [Subquery] {
        if case .compound(let compound) = self {
            return compound.subqueries
        } else {
            fatalError("Tried to get subqueries for a non-compound query: \(self)")
        }
    }
}
