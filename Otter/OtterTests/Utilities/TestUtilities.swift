//
//  TestUtilities.swift
//  OtterTests
//
//  Created by Tim Mahoney on 1/8/24.
//

import Foundation
import Otter
import XCTest
import Zip

public func OTAssert(_ expression: @autoclosure () async throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
    let result = try await expression()
    XCTAssert(result, message(), file: file, line: line)
}

public func OTAssertEqual<T>(_ expression1: @autoclosure () async throws -> T, _ expression2: @autoclosure () async throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws where T : Equatable {
    let result1 = try await expression1()
    let result2 = try await expression2()
    XCTAssertEqual(result1, result2, message(), file: file, line: line)
}

// MARK: - Helpers

extension XCTestCase {
    
    public func newDatabase() -> Database {
        return Database()
    }
    
    public func newDatabase(_ archiveURL: URL) async throws -> Database {
        let database = Database()
        database.addLogarchive(archiveURL)
        try await database.loadLogarchivesIfNecessary()
        return database
    }
    
    public func newDatabase(entries: Int) throws -> Database {
        let database = Database.sampleDatabase(entries)
        return database
    }
    
    func fileURL(_ name: String, _ pathExtension: String) throws -> URL {
        let bundle = Bundle(for: type(of: self))
        let fileURL = bundle.url(forResource: name, withExtension: pathExtension)
        if let fileURL {
            return fileURL
        } else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [ NSLocalizedDescriptionKey : "Missing test resource. This is likely a set test logs that were deleted for privacy reasons. See TODO by sampleSmallLogarchiveFileURL." ])
        }
    }
    
    func unzippedFileURL(_ name: String, _ pathExtension: String) throws -> URL {
        var pathExtensionWithoutZip = pathExtension
        pathExtensionWithoutZip.replace(".zip", with: "")
        pathExtensionWithoutZip.replace(".tar.gz", with: "")
        let unzippedURL = FileManager.default.temporaryDirectory.appending(component: name).appendingPathExtension(pathExtensionWithoutZip)
        let alreadyUnzipped = (try? unzippedURL.checkResourceIsReachable()) ?? false
        if alreadyUnzipped {
            return unzippedURL
        }
        let url = try fileURL(name, pathExtension)
        
        try Zip.unzipFile(url, destination: unzippedURL.deletingLastPathComponent(), overwrite: true, password: nil)
        return unzippedURL
    }
    
    // MARK: - Sample Log Archives
    
    // TODO: These were deleted for privacy reasons. We should find a way to get some good sample data for the tests.
    // If you're reading this, you can generate some sample log archives yourself and add them to the test target.
    // Or, ideally, you can find a way to include or generate test logs in a security/privacy-aware manner.
    
    var sampleSmallLogarchiveFileURL: URL {
        get throws { try self.unzippedFileURL("sample-small", "logarchive.zip") }
    }
    
    var sampleMillionLogarchiveFileURL: URL {
        get throws { try self.unzippedFileURL("sample-million", "logarchive.zip") }
    }
    
    var sampleiOSSysdiagnoseLogarchiveFileURL: URL {
        get throws { try self.unzippedFileURL("sample-iossysdiagnose", "logarchive.zip") }
    }
}
