//
//  UtilitiesTests.swift
//  OtterTests
//
//  Created by Tim Mahoney on 1/22/24.
//

import Foundation
import XCTest
import os
import Otter

final class UtilitiesTests : XCTestCase {
    
    // MARK: - Array
    
    func testIndexSetArraySubscript() {
        let array = [0, 1, 2, 3]
        
        let empty = IndexSet()
        XCTAssertEqual(array[empty], [])
        
        let zero = IndexSet([0])
        XCTAssertEqual(array[zero], [0])
        
        let one = IndexSet([1])
        XCTAssertEqual(array[one], [1])
        
        let zeroOne = IndexSet([0, 1])
        XCTAssertEqual(array[zeroOne], [0, 1])
        
        let zeroTwo = IndexSet([0, 2])
        XCTAssertEqual(array[zeroTwo], [0, 2])
        
        let oneTwo = IndexSet([1, 2])
        XCTAssertEqual(array[oneTwo], [1, 2])
        
        let oneThree = IndexSet([1, 3])
        XCTAssertEqual(array[oneThree], [1, 3])
        
        let all = IndexSet([0, 1, 2, 3])
        XCTAssertEqual(array[all], [0, 1, 2, 3])
    }
    
    func testIndexSetArraySubscript_VeryLarge() {
        let count = 1_000_000
        let array = (0..<count).map { $0 }
        
        let iterationCount = 10
        
        for _ in 0..<iterationCount {
            let approximateIndexSetSize = count / 10
            var indexSet = IndexSet()
            for _ in 0..<approximateIndexSetSize {
                indexSet.insert(Int.random(in: 0..<count))
            }
            
            let elements = array[indexSet]
            XCTAssertEqual(elements, indexSet.sorted())
        }
    }
    
    func testBinarySearch() {
        // Some simple base cases.
        XCTAssertEqual([0].ot_binaryFirstIndex { $0 == 0 }, 0)
        XCTAssertEqual([0, 1].ot_binaryFirstIndex { $0 == 0 }, 0)
        XCTAssertEqual([0, 1].ot_binaryFirstIndex { $0 == 1 }, 1)
        XCTAssertEqual([0, 1, 2].ot_binaryFirstIndex { $0 == 0 }, 0)
        XCTAssertEqual([0, 1, 2].ot_binaryFirstIndex { $0 == 1 }, 1)
        XCTAssertEqual([0, 1, 2].ot_binaryFirstIndex { $0 == 2 }, 2)
        
        // Check a bunch of stuff for a 100-element array.
        let values = (0..<100).map { $0 }
        
        XCTAssertNil(values.ot_binaryFirstIndex { $0 < 0 })
        XCTAssertNil(values.ot_binaryFirstIndex { $0 > 100 })
        
        for i in values {
            let index = values.ot_binaryFirstIndex { $0 == i }
            XCTAssertEqual(index, i)
            
            let greaterThanIndex = values.ot_binaryFirstIndex { $0 > i }
            if i >= values.count - 1 {
                XCTAssertNil(greaterThanIndex)
            } else {
                XCTAssertEqual(greaterThanIndex, i + 1)
            }
            
            let lessThanIndex = values.ot_binaryFirstIndex { $0 < i }
            if i == 0 {
                XCTAssertNil(lessThanIndex)
            } else {
                XCTAssertEqual(lessThanIndex, 0)
            }
        }
        
        XCTAssertNil([].ot_binaryFirstIndex { $0 == 0 })
        XCTAssertNil([1].ot_binaryFirstIndex { $0 == 0 })
        
        for size in 0...10 {
            let sizedValues = (0..<size).map { $0 }
            XCTAssertNil(sizedValues.ot_binaryFirstIndex { $0 < 0 })
            XCTAssertNil(sizedValues.ot_binaryFirstIndex { $0 > size })
            for i in sizedValues {
                let index = values.ot_binaryFirstIndex { $0 == i }
                XCTAssertEqual(index, i)
                
                let greaterThanIndex = values.ot_binaryFirstIndex { $0 > i }
                if i >= values.count - 1 {
                    XCTAssertNil(greaterThanIndex)
                } else {
                    XCTAssertEqual(greaterThanIndex, i + 1)
                }
                
                let lessThanIndex = values.ot_binaryFirstIndex { $0 < i }
                if i == 0 {
                    XCTAssertNil(lessThanIndex)
                } else {
                    XCTAssertEqual(lessThanIndex, 0)
                }
            }
        }
    }
    
    func testBinarySearchPerformance() {
        let sizes = [100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000]
        let valueArrays = sizes.map { (0..<$0).map { $0 } }

        for values in valueArrays {
            let start = Date.now
            self.testSearchThingy(values) { $0.ot_binaryFirstIndex(where: $1) }
            print("binary(\(values.count.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))) = \(String(format: "%.2fs", -start.timeIntervalSinceNow))")
        }
        
        Thread.sleep(forTimeInterval: 1)
        
        for values in valueArrays {
            let start = Date.now
            self.testSearchThingy(values) { $0.firstIndex(where: $1) }
            print("firstIndex \(values.count.formatted().padding(toLength: 10, withPad: " ", startingAt: 0))\t= \(String(format: "%.2fs", -start.timeIntervalSinceNow))")
        }
    }
    
    func testSearchThingy(_ values: [Int], _ block: ([Int], ((Int) -> Bool)) -> [Int].Index?) {
        let count = values.count
        let targetValues = [0, count / 4, count / 2, count * 3 / 4, count - 1]
        for i in targetValues {
            let index = block(values, { $0 == i })
            XCTAssertEqual(index, i)
            
            let greaterThanIndex = block(values, { $0 > i })
            if i >= values.count - 1 {
                XCTAssertNil(greaterThanIndex)
            } else {
                XCTAssertEqual(greaterThanIndex, i + 1)
            }
            
            let lessThanIndex = block(values, { $0 < i })
            if i == 0 {
                XCTAssertNil(lessThanIndex)
            } else {
                XCTAssertEqual(lessThanIndex, 0)
            }
        }
    }
    
    // MARK: - Fast Parsing
    
    func testFastLogParsing_Small() async throws {
        let small = try self.sampleSmallLogarchiveFileURL
        try await self.testFastLogParsing(fileURL: small, expected: 397_573)
    }
    
    func testFastLogParsing_Million() async throws {
        let million = try self.sampleMillionLogarchiveFileURL
        try await self.testFastLogParsing(fileURL: million, expected: 1_001_139)
    }
    
    func testFastLogParsing_Sysdiagnose() async throws {
        let sysdiagnose = try self.sampleiOSSysdiagnoseLogarchiveFileURL
        try await self.testFastLogParsing(fileURL: sysdiagnose, expected: 6_291_656)
    }
    
    func testFastLogParsing(fileURL: URL, expected: Int) async throws {
        let iterations = 3
        
        for _ in 0..<iterations {
            try await self.testFastLogParsing(fileURL, expected: expected, chunks: 40, power: 1.2, concurrent: 8)
        }
    }
    
    func testFastLogParsing(_ fileURL: URL, expected: Int, chunks: Int, power: Double, concurrent: Int) async throws {
        try XCTSkipIf(true, "TODO: Remove?")
        
        let start = Date.now
        let countLock = OSAllocatedUnfairLock(initialState: 0)
        
        try await OtterFastEnumeration.fastEnumerate(
            fileURL,
            chunks: chunks,
            power: power,
            concurrent: concurrent,
            progresses: [:]
        ) { start, end in
            print("Got start=\(start) end=\(end)")
        } block: { batchIndex, systemEntry in
            if let entry = Entry(systemEntry: systemEntry) {
                let count = countLock.withLock { $0 += 1; return $0 }
                if count % 100_000 == 0 {
                    print("Loaded \(count.formatted()) entries")
                }
                return entry
            } else {
                return nil
            }
        } finishedChunk: { batchIndex, totalChunks, chunk in
            print("Finished batch \(batchIndex) out of \(totalChunks)")
        }
        let count = countLock.withLock { $0 }
        
        let end = Date.now
        print("=== FAST PARSE PERFORMANCE chunks=\(chunks) power=\(power) concurrent=\(concurrent) time=\(end.timeIntervalSince(start).formatted())")
        
        XCTAssertEqual(count, expected)
    }
}
