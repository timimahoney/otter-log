//
//  Entry.swift
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

import Foundation
import OSLog

public struct Entry : Codable, Sendable {
    public let type: EventType
    
    public var date: Date
    public var message: String
    public var activityIdentifier: os_activity_id_t
    public var process: String
    public var processIdentifier: pid_t
    public var sender: String
    public var threadIdentifier: UInt
    
    // Activity
    public var parentActivityIdentifier: os_activity_id_t?
    
    // Log
    var levelValue: Int?
    public var subsystem: String?
    public var category: String?
    
#if OTTER_SIGNPOSTS
    // Signpost
    public var signpostIdentifier: os_signpost_id_t?
    public var signpostName: String?
    var signpostTypeValue: Int?
#endif
    
    public init(
        type: EventType,
        date: Date,
        message: String,
        activityIdentifier: os_activity_id_t,
        process: String,
        processIdentifier: pid_t,
        sender: String,
        threadIdentifier: UInt,
        parentActivityIdentifier: os_activity_id_t? = nil,
        level: OSLogEntryLog.Level? = nil,
        subsystem: String? = nil,
        category: String? = nil,
        signpostIdentifier: os_signpost_id_t? = nil,
        signpostName: String? = nil,
        signpostType: OSLogEntrySignpost.SignpostType? = nil
    ) {
        self.date = date
        self.message = message
        self.activityIdentifier = activityIdentifier
        self.process = process
        self.processIdentifier = processIdentifier
        self.sender = sender
        self.threadIdentifier = threadIdentifier
        self.parentActivityIdentifier = parentActivityIdentifier
        self.levelValue = level?.rawValue
        self.subsystem = subsystem
        self.category = category
#if OTTER_SIGNPOSTS
        self.signpostIdentifier = signpostIdentifier
        self.signpostName = signpostName
        let signpostTypeValue = signpostType?.rawValue
        self.signpostTypeValue = signpostTypeValue
#endif
        
        self.type = type
    }
}

@objc(OTEntryBox)
public class EntryBox : NSObject {
    let entry: Entry
    public init(_ entry: Entry) {
        self.entry = entry
    }
}
extension Entry {
    
    init?(osLogEntry: OSLogEntry) {
        guard let fromProcess = osLogEntry as? OSLogEntryFromProcess else {
            return nil
        }
        
        let log = osLogEntry as? OSLogEntryLog
        let activity = osLogEntry as? OSLogEntryActivity
#if OTTER_SIGNPOSTS
        let signpost = osLogEntry as? OSLogEntrySignpost
#endif
        let withPayload = osLogEntry as? OSLogEntryWithPayload
        
        let date = osLogEntry.date
        let message = osLogEntry.composedMessage
        let activityIdentifier = fromProcess.activityIdentifier
        let process = fromProcess.process
        let processIdentifier = fromProcess.processIdentifier
        let sender = fromProcess.sender
        let threadIdentifier = UInt(fromProcess.threadIdentifier)
        let parentActivityIdentifier = activity?.parentActivityIdentifier ?? 0
        let level = log?.level
        let subsystem = withPayload?.subsystem
        let category = withPayload?.category
#if OTTER_SIGNPOSTS
        let signpostIdentifier = signpost?.signpostIdentifier
        let signpostName = signpost?.signpostName
        let signpostType = signpost?.signpostType
#endif
        
        let type: EventType
        if activity != nil {
            type = .activity
        } else {
            type = .log
        }
        
#if OTTER_SIGNPOSTS
        // Somewhere in there...
//    } else if signpost != nil {
        type = .signpost
//    }
#endif
        
        self.type = type
        self.date = date
        self.message = message.stringocchioWantsToBeARealBoy
        self.activityIdentifier = activityIdentifier
        self.process = process.stringocchioWantsToBeARealBoy
        self.processIdentifier = processIdentifier
        self.sender = sender.stringocchioWantsToBeARealBoy
        self.threadIdentifier = threadIdentifier
        self.parentActivityIdentifier = parentActivityIdentifier
        self.levelValue = level?.rawValue
        self.subsystem = subsystem?.stringocchioWantsToBeARealBoy
        self.category = category?.stringocchioWantsToBeARealBoy
#if OTTER_SIGNPOSTS
        self.signpostIdentifier = signpostIdentifier
        self.signpostName = signpostName?.stringocchioWantsToBeARealBoy
        self.signpostTypeValue = signpostType?.rawValue
#endif
    }
    
    public init?(systemEntry: OTSystemLogEntry, knownProcesses: OSAllocatedUnfairLock<[UUID : String]>? = nil) {
        // The `process` getter is really slow because it looks up via UUID every time or something.
        // Let's speed that up a bit.
        let process: String?
        if let uuid = systemEntry.processImageUUID {
            process = knownProcesses?.withLock {
                if let knownProcess = $0[uuid] {
                    return knownProcess
                } else {
                    if let newProcess = systemEntry.process?.stringocchioWantsToBeARealBoy {
                        $0[uuid] = newProcess
                        return newProcess
                    } else {
                        return nil
                    }
                }
            }
        } else {
            // We shoudn't ever get here, but who knows.
            process = systemEntry.process
        }
        
        guard let process else {
            return nil
        }
        
        let date = systemEntry.date
        let message = systemEntry.composedMessage
        let activityIdentifier = systemEntry.activityIdentifier
        let processIdentifier = systemEntry.processIdentifier
        let sender = systemEntry.sender
        let threadIdentifier = UInt(systemEntry.threadIdentifier)
        let parentActivityIdentifier = systemEntry.parentActivityIdentifier
        
        let subsystem = systemEntry.subsystem
        let category = systemEntry.category
        let signpostIdentifier = systemEntry.signpostIdentifier
        let signpostName = systemEntry.signpostName
        let signpostType = systemEntry.signpostType
        
        let level: OSLogEntryLog.Level?
        let type: EventType
        switch systemEntry.type {
        case .activity:
            type = .activity
            level = nil
        case .log:
            type = .log
            level = systemEntry.logType.level
        @unknown default:
            Logger.data.info("Unknown log type from system: \(systemEntry.logType.rawValue)")
            return nil
        }
        
        self.type = type
        self.date = date
        self.message = message.stringocchioWantsToBeARealBoy
        self.activityIdentifier = activityIdentifier
        self.process = process.stringocchioWantsToBeARealBoy
        self.processIdentifier = processIdentifier
        self.sender = sender.stringocchioWantsToBeARealBoy
        self.threadIdentifier = threadIdentifier
        self.parentActivityIdentifier = parentActivityIdentifier
        self.levelValue = level?.rawValue
        self.subsystem = subsystem?.stringocchioWantsToBeARealBoy
        self.category = category?.stringocchioWantsToBeARealBoy
#if OTTER_SIGNPOSTS
        self.signpostIdentifier = signpostIdentifier
        self.signpostName = signpostName?.stringocchioWantsToBeARealBoy
        self.signpostTypeValue = signpostType == 0 ? nil : Int(signpostType)
#endif
    }
}

// MARK: - Value Conversions

extension Entry {
    
    public enum EventType : Int16, Hashable, Codable, Sendable {
        case log
        case activity
#if OTTER_SIGNPOSTS
        case signpost
#endif
    }
    
#if OTTER_SIGNPOSTS
    public var signpostType: OSLogEntrySignpost.SignpostType? {
        get {
            if let signpostTypeValue = self.signpostTypeValue, signpostTypeValue != 0 {
                return OSLogEntrySignpost.SignpostType(rawValue: Int(signpostTypeValue))
            } else {
                return nil
            }
        }
        set {
            if let newValue {
                self.signpostTypeValue = Int(newValue.rawValue)
            } else {
                self.signpostTypeValue = nil
            }
        }
    }
#endif // OTTER_SIGNPOSTS
    
    public var level: OSLogEntryLog.Level {
        get {
            if let value = self.levelValue {
                return OSLogEntryLog.Level(rawValue: value) ?? .undefined
            } else {
                return .undefined
            }
        }
        set {
            self.levelValue = newValue.rawValue
        }
    }
}

// MARK: - Hashable / Equatable

extension Entry : Hashable {
    
}

// MARK: - Entry.Property

extension Entry {
    
    public enum Property : String, CaseIterable {
        case type       = "Type"
        case date       = "Date"
        case activity   = "Activity"
        case process    = "Process"
        case pid        = "PID"
        case thread     = "Thread"
        case subsystem  = "Subsystem"
        case category   = "Category"
        case message    = "Message"
    }
}

extension Entry.Property {
    
    var queryProperty: PropertyQuery.Property? {
        switch self {
        case .type, .date:
            return nil
        case .activity:
            return .activity
        case .process:
            return .process
        case .pid:
            return .pid
        case .thread:
            return .thread
        case .subsystem:
            return .subsystem
        case .category:
            return .category
        case .message:
            return .message
        }
    }
}

// MARK: - Convenience

extension Entry {
    
    /// A text representation of this entry that includes the date, process, thread, message, etc.
    ///
    /// This is used when copying from the list and for showing in the selected logs view.
    ///
    /// For example:
    /// ```
    /// 2024-01-10 11:14:38.831786-0800 0x724d65   Error       0x0                  18248  14   knowledgeconstructiond: (CoreData) [com.apple.coredata:error] error:   file is not a symbolic link
    /// ```
    public var plaintextRepresentation: String {
        // Date
        var string = "\(Date.otterDateString(self.date)) "
        
        // Thread
        string += String(format: "0x%x", self.threadIdentifier).padding(toLength: 11, withPad: " ", startingAt: 0)
        
        // Type
        string += self.typeString.padding(toLength: 12, withPad: " ", startingAt: 0)
        
        // Activity
        let activityString = "\(self.activityIdentifier)".padding(toLength: 10, withPad: " ", startingAt: 0)
        string += "\(activityString) "
        
        // PID
        let pidString = "\(self.processIdentifier)".padding(toLength: 6, withPad: " ", startingAt: 0)
        string += "\(pidString) "
        
#if OTTER_SIGNPOSTS
        if self.type == .signpost {
            let signpostIDString: String
            let signpostID = self.signpostIdentifier ?? 0
            if signpostID == OSSignpostID.exclusive.rawValue {
                signpostIDString = "excl"
            } else {
                signpostIDString = String(format: "0x%x", signpostID)
            }
            let signpostTypeName: String
            switch self.signpostType {
            case .intervalBegin:
                signpostTypeName = "begin"
            case .event:
                signpostTypeName = "event"
            case .intervalEnd:
                signpostTypeName = "  end"
            case .undefined, .none, .some(_):
                signpostTypeName = "unkwn"
            }
            string += "[spid \(signpostIDString), process, \(signpostTypeName)] "
        }
#endif
        
        // Process, sender
        string += "\(self.process): (\(self.sender)) "
        
        // Subsystem, category
        if let subsystem = self.subsystem, let category = self.category {
            string += "[\(subsystem):\(category)] "
        }
        
#if OTTER_SIGNPOSTS
        if let signpostName = self.signpostName {
            string += "\(signpostName): "
        }
#endif
        
        // Message
        string += self.message
        
        return string
    }
    
    var typeString: String {
        switch self.type {
        case .log:
            switch self.level {
            case .undefined:
                "Unknown"
            case .debug:
                "Debug"
            case .info:
                "Info"
            case .notice:
                "Default"
            case .error:
                "Error"
            case .fault:
                "Fault"
            @unknown default:
                "Unknown"
            }
        case .activity:
            "Activity"
#if OTTER_SIGNPOSTS
        case .signpost:
            "Signpost"
#endif
        }
    }
}
