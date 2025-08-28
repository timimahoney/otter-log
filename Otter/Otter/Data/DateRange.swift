//
//  DateRange.swift
//  Otter
//
//  Created by Tim Mahoney on 2/15/24.
//

import Foundation
import SwiftUI

public enum DateRange : String, Identifiable, Hashable, Sendable {
    public var id: Self { self }
    
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case hour
    case fourHours
    case eightHours
    case day
    case all
    case custom
    
    public var timeIntervalBeforeEnd: TimeInterval? {
        switch self {
        case .fiveMinutes:          5 * 60
        case .fifteenMinutes:      15 * 60
        case .thirtyMinutes:       30 * 60
        case .hour:            1 * 60 * 60
        case .fourHours:       4 * 60 * 60
        case .eightHours:      8 * 60 * 60
        case .day:            24 * 60 * 60
        case .all, .custom:            nil
        }
    }
    
    public var nameKey: String {
        switch self {
        case .fiveMinutes:      "Last 5 Minutes"
        case .fifteenMinutes:   "Last 15 Minutes"
        case .thirtyMinutes:    "Last 30 Minutes"
        case .hour:             "Last Hour"
        case .fourHours:        "Last 4 Hours"
        case .eightHours:       "Last 8 Hours"
        case .day:              "Last Day"
        case .all:              "All"
        case .custom:           "Custom"
        }
    }
    
    var approximateLogCount: Int? {
        if let timeIntervalSinceEnd = self.timeIntervalBeforeEnd {
            if timeIntervalSinceEnd <= (10 * 60) {
                return 200_000
            } else if timeIntervalSinceEnd <= (1 * 60 * 60) {
                return 1_000_000
            } else if timeIntervalSinceEnd <= (24 * 60 * 60) {
                return 2_000_000
            } else {
                return 5_000_000
            }
        } else {
            return 5_000_000
        }
    }
    
    public func knownRange(end: Date) -> ClosedRange<Date>? {
        switch self {
        case .all:
            return .distantRange
        case .custom:
            return nil
        default:
            if let timeIntervalBeforeEnd = self.timeIntervalBeforeEnd {
                let start = end.addingTimeInterval(-timeIntervalBeforeEnd)
                return start...end
            } else {
                return nil
            }
        }
    }
}

// MARK: - Comparable

extension DateRange : Comparable {
    public static func < (lhs: DateRange, rhs: DateRange) -> Bool {
        return lhs.comparisonTimeInterval < rhs.comparisonTimeInterval
    }
    
    private var comparisonTimeInterval: TimeInterval {
        if let timeIntervalBeforeEnd = self.timeIntervalBeforeEnd {
            return timeIntervalBeforeEnd
        } else {
            return .infinity
        }
    }
}

// MARK: -

extension DateRange : CustomStringConvertible {
    
    public var description: String {
        return "\(self.nameKey)"
    }
}
