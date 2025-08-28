//
//  EntryTests.swift
//  OtterTests
//
//  Created by Tim Mahoney on 1/18/24.
//

import XCTest
import Otter

final class EntryTests: XCTestCase {

    func testPlaintextRepresentation() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1234.5678987654)
        
        //
        // Logs
        //
        
        // Debug. Short process name. No activity.
        var entry = Entry(type: .log, date: date, message: "i am a log", activityIdentifier: 0, process: "Otter", processIdentifier: 123, sender: "Otter", threadIdentifier: 89217, level: .debug, subsystem: "com.jollycode.otter", category: "data")
        var plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0x15c81    Debug       0          123    Otter: (Otter) [com.jollycode.otter:data] i am a log")
        
        // Info. Long process name. Activity.
        entry = Entry(type: .log, date: date, message: "i am not a log?", activityIdentifier: 3828, process: "cloudd", processIdentifier: 8765, sender: "CloudKit", threadIdentifier: 913843, level: .info, subsystem: "com.apple.cloudkit", category: "CK")
        plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0xdf1b3    Info        3828       8765   cloudd: (CloudKit) [com.apple.cloudkit:CK] i am not a log?")
        
        // Default.
        entry = Entry(type: .log, date: date, message: "i am a log, you know, like wood and stuff", activityIdentifier: 0, process: "Otter", processIdentifier: 2, sender: "SwiftUI", threadIdentifier: 45328, level: .notice, subsystem: "com.apple.swiftui", category: "redraw")
        plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0xb110     Default     0          2      Otter: (SwiftUI) [com.apple.swiftui:redraw] i am a log, you know, like wood and stuff")
        
        // Error.
        entry = Entry(type: .log, date: date, message: "what are you doing", activityIdentifier: 123, process: "Otter", processIdentifier: 3, sender: "Otter", threadIdentifier: 912311, level: .error, subsystem: "com.jollycode.otter", category: "ui")
        plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0xdebb7    Error       123        3      Otter: (Otter) [com.jollycode.otter:ui] what are you doing")
        
        // Fault.
        entry = Entry(type: .log, date: date, message: "nobody knows what went wrong", activityIdentifier: 55555, process: "Otter", processIdentifier: 4444, sender: "Otter", threadIdentifier: 22222, level: .fault, subsystem: "com.jollycode.otter", category: "data")
        plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0x56ce     Fault       55555      4444   Otter: (Otter) [com.jollycode.otter:data] nobody knows what went wrong")
        
        //
        // Activity
        //
        entry = Entry(type: .activity, date: date, message: "engine/send-changes", activityIdentifier: 55555, process: "Otter", processIdentifier: 3333, sender: "CloudKit", threadIdentifier: 333)
        plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0x14d      Activity    55555      3333   Otter: (CloudKit) engine/send-changes")
        
#if OTTER_SIGNPOSTS
        //
        // Signpost
        //
        
        // Begin
        entry = Entry(type: .signpost, date: date, message: "enableTelemetry=YES", activityIdentifier: 55555, process: "appleaccountd", processIdentifier: 1036, sender: "CoreCDP", threadIdentifier: 333, subsystem: "com.apple.cdp", category: "signpost", signpostIdentifier: 432, signpostName: "OctagonStatus", signpostType: .intervalBegin)
        plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0x14d      Signpost    55555      1036   [spid 0x1b0, process, begin] appleaccountd: (CoreCDP) [com.apple.cdp:signpost] OctagonStatus: enableTelemetry=YES")
        
        // Event
        entry = Entry(type: .signpost, date: date, message: "enableTelemetry=YES", activityIdentifier: 55555, process: "appleaccountd", processIdentifier: 1036, sender: "CoreCDP", threadIdentifier: 333, subsystem: "com.apple.cdp", category: "signpost", signpostIdentifier: 2812038128, signpostName: "OctagonStatus", signpostType: .event)
        plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0x14d      Signpost    55555      1036   [spid 0xa79c4bf0, process, event] appleaccountd: (CoreCDP) [com.apple.cdp:signpost] OctagonStatus: enableTelemetry=YES")
        
        // End. Exclusive ID.
        entry = Entry(type: .signpost, date: date, message: "enableTelemetry=YES", activityIdentifier: 55555, process: "appleaccountd", processIdentifier: 1036, sender: "CoreCDP", threadIdentifier: 333, subsystem: "com.apple.cdp", category: "signpost", signpostIdentifier: OSSignpostID.exclusive.rawValue, signpostName: "OctagonStatus", signpostType: .intervalEnd)
        plaintext = entry.plaintextRepresentation
        XCTAssertEqual(plaintext, "2000-12-31 16:20:34.567898-0800 0x14d      Signpost    55555      1036   [spid excl, process,   end] appleaccountd: (CoreCDP) [com.apple.cdp:signpost] OctagonStatus: enableTelemetry=YES")
#endif // OTTER_SIGNPOSTS
    }
}
