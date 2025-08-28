//
//  LogLevelQuery.swift
//  Otter
//
//  Created by Tim Mahoney on 2/1/24.
//

import Foundation

// MARK: - LogLevelQuery

public struct LogLevelQuery: Codable, Hashable, Sendable {
    
    var id = UUID()
    
    var logLevelValues: Set<Int> = []
    
    var logLevels: Set<OSLogEntryLog.Level> {
        get { Set(self.logLevelValues.map { OSLogEntryLog.Level(rawValue: $0) ?? .undefined }) }
        set { self.logLevelValues = Set(newValue.map { $0.rawValue }) }
    }
}

// MARK: - Initialization Helpers

extension LogLevelQuery {
    
    public static func logLevels(_ levels: [OSLogEntryLog.Level]) -> LogLevelQuery {
        return LogLevelQuery(logLevelValues: Set(levels.map { $0.rawValue }))
    }
}

// MARK: - Description

extension LogLevelQuery : CustomStringConvertible {
    
    public var description: String {
        return "(level IN [\(self.logLevels.map { $0.description })])"
    }
    
    public var predicateString: String {
        let logLevelNames = self.logLevels.map { $0.description.lowercased() }.joined(separator: ", ")
        return "(messageType IN {\(logLevelNames)})"
    }
}

extension OSLogEntryLog.Level : @retroactive CustomStringConvertible, @retroactive Identifiable, @retroactive Equatable {
    
    public var description: String {
        switch self {
        case .debug:      "Debug"
        case .info:       "Info"
        case .notice:     "Log"
        case .error:      "Error"
        case .fault:      "Fault"
        case .undefined:  "Undefined"
        @unknown default: "Unknown"
        }
    }
    
    public var compactDescription: String {
        switch self {
        case .debug:      "Dbg"
        case .info:       "Inf"
        case .notice:     "Log"
        case .error:      "Err"
        case .fault:      "Flt"
        case .undefined:  "Undf"
        @unknown default: "Unk"
        }
    }
    
    public var id: String { self.description }
}

// MARK: - Evaluation

extension LogLevelQuery {
    
    func evaluate(_ entry: Entry, _ context: FilterContext) -> Bool {
        if self.logLevelValues.isEmpty {
            return true
        } else {
            return self.logLevelValues.contains(entry.level.rawValue)
        }
    }
}
