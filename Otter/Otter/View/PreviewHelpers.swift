//
//  PreviewHelpers.swift
//  Otter
//
//  Created by Tim Mahoney on 2/6/24.
//

import Foundation
import SwiftUI

// TODO: Don't compile for release

extension Database {
    
    public static func sampleDatabase(_ entryCount: Int = 10_000) -> Database {
        let entries = Self.sampleData(entryCount)
        let database = Database(entries: entries)
        return database
    }
    
    static func sampleData(_ entryCount: Int) -> [Entry] {
        return self._sampleData(entryCount)
    }
    
    static func _sampleData(_ entryCount: Int = 10_000) -> [Entry] {
        let start = Date.now.addingTimeInterval(-24 * 60 * 60)
        let end = Date.now
        let duration = end.timeIntervalSince(start)
        var entries: [Entry] = []
        
        let subsystems = [
            "com.jollycode.db" : [
                "App",
                "Otter",
                "NowNow",
            ],
            "com.jollycode.otter": [
                "Otter",
                "App",
                "View",
                "Data",
                "Misc",
                "Sync",
            ],
            "com.jollycode.nownow": [
                "NowNow",
                "App",
                "View",
                "Data",
                "Misc",
                "Sync",
            ],
            "com.apple.cloudkit": [
                "CK",
                "Operation",
                "Engine",
            ],
        ]
        
        let messages = [
            "1 is the loneliest number at the zero index",
            "2 -- if I'm being honest -- is filled with poo",
            "3 is the magic number string",
            "4 is when I start wondering how much sample data I'll need...",
            "5 is when I stop",
            "6 is when I add a log that spans...how do you say...\n...multiple...\n...lines?",
            "7 is when I add a log that is really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really really wide",
        ]
        
        let processes = [
            "Otter",
            "NowNow",
            "cloudd",
            "accountsd",
            "com.apple.Safari.SafariBookmarksSyncAgent",
            "runningboardd",
        ]
        
        // Keep track of our activity count so that we know what the next activity ID should be.
        var activityCount: os_activity_id_t = 0
        
        for _ in (0..<entryCount) {
            guard let subsystem = subsystems.keys.randomElement() else { fatalError("No random subsystem") }
            guard let category = subsystems[subsystem]?.randomElement() else { fatalError("No random category") }
            guard let message = messages.randomElement() else { fatalError("No random message") }
            guard let process = processes.randomElement() else { fatalError("No random process") }
            
            let timeInterval = start.timeIntervalSinceReferenceDate + TimeInterval.random(in: 0..<duration)
            let pid = pid_t.random(in: 0..<3000)
            
            var activityID: os_activity_id_t = 0
            let shouldLogBeInActivity = (Int.random(in: 0..<5) == 0)
            if shouldLogBeInActivity {
                var parentActivityIdentifier: os_activity_id_t? = nil
                let shouldCreateNewActivity = (activityCount == 0) || (Int.random(in: 0..<5) == 0)
                if shouldCreateNewActivity {
                    let shouldBeChildActivity = (activityCount > 0) && (Int.random(in: 0..<2) == 0)
                    if shouldBeChildActivity {
                        parentActivityIdentifier = activityCount
                    }
                    activityCount += 1
                }
                
                activityID = activityCount
                
                if shouldCreateNewActivity {
                    let activityEntry = Entry(
                        type: .activity,
                        date: Date(timeIntervalSinceReferenceDate: timeInterval),
                        message: "my/activity-\(activityCount)",
                        activityIdentifier: activityID,
                        process: process,
                        processIdentifier: pid,
                        sender: "Bopbop",
                        threadIdentifier: 0,
                        parentActivityIdentifier: parentActivityIdentifier
                    )
                    entries.append(activityEntry)
                }
            }
            
            let logEntry = Entry(
                type: .log,
                date: Date(timeIntervalSinceReferenceDate: timeInterval),
                message: message,
                activityIdentifier: activityID,
                process: process,
                processIdentifier: pid,
                sender: "BeepBoop",
                threadIdentifier: .random(in: 0..<64_646),
                level: OSLogEntryLog.Level(rawValue: Int(pid % 6)) ?? .undefined,
                subsystem: subsystem,
                category: category
            )
            entries.append(logEntry)
        }
        
        return entries
    }
}

extension FilteredData {
    
    static func previewData() -> FilteredData {
        let database = Database.sampleDatabase()
        var data = FilteredData(database)
        let end = database.range.upperBound
        let start = end - (5 * 60)
        data.userSelectedRange = start...end
        asyncAntipattern {
            try! await data.regenerateEntries()
            try! data.regenerateActivities()
        }
        return data
    }
}

struct PreviewBindingHelper<Value, Content: View>: View {
    @State var value: Value
    var content: (Binding<Value>) -> Content

    var body: some View {
        self.content(self.$value)
    }

    init(_ value: Value, content: @escaping (Binding<Value>) -> Content) {
        self._value = State(wrappedValue: value)
        self.content = content
    }
}
