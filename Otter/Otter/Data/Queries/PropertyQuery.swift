//
//  PropertyQuery.swift
//  Otter
//
//  Created by Tim Mahoney on 2/1/24.
//

import Foundation

public struct PropertyQuery : Codable, Hashable, Sendable {
    
    var id: UUID
    
    public var property: Property
    public var comparison: Comparison = .contains
    public var value: String = ""
    
    public enum Property : Codable, Hashable, CaseIterable, Sendable {
        case subsystem
        case category
        case message
        case process
        case pid
        case sender
        case activity
        case thread
    }
    
    public enum Comparison : Int, Codable, Hashable, CaseIterable, Sendable {
        case contains
        case equals
        case doesNotContain
        case doesNotEqual
    }
    
    public init(property: Property, comparison: Comparison, value: String) {
        self.property = property
        self.comparison = comparison
        self.value = value.stringocchioWantsToBeARealBoy
        self.id = UUID()
    }
}

// MARK: - Initialization Helpers

extension PropertyQuery {
    
    public static func contains(_ property: Property, _ value: String) -> PropertyQuery {
        return PropertyQuery(property: property, comparison: .contains, value: value)
    }
    
    public static func equals(_ property: Property, _ value: String) -> PropertyQuery {
        return PropertyQuery(property: property, comparison: .equals, value: value)
    }
    
    public static func doesNotContain(_ property: Property, _ value: String) -> PropertyQuery {
        return PropertyQuery(property: property, comparison: .doesNotContain, value: value)
    }
    
    public static func doesNotEqual(_ property: Property, _ value: String) -> PropertyQuery {
        return PropertyQuery(property: property, comparison: .doesNotEqual, value: value)
    }
}

// MARK: - Property / Comparison Variant

extension PropertyQuery.Property : Identifiable {
    
    var name: String {
        switch self {
        case .subsystem:      "Subsystem"
        case .category:       "Category"
        case .message:        "Message"
        case .process:        "Process"
        case .pid:            "PID"
        case .sender:         "Sender"
        case .activity:       "Activity"
        case .thread:         "Thread"
        }
    }
    
    var compactName: String {
        switch self {
        case .subsystem:      "S"
        case .category:       "C"
        case .message:        "M"
        case .process:        "P"
        case .pid:            "PID"
        case .sender:         "S"
        case .activity:       "A"
        case .thread:         "T"
        }
    }
    
    var logPredicateKeyPath: String {
        switch self {
        case .subsystem:      "subsystem"
        case .category:       "category"
        case .message:        "message"
        case .process:        "process"
        case .pid:            "processIdentifier"
        case .sender:         "sender"
        case .activity:       "activity"
        case .thread:         "thread"
        }
    }
    
    public var id: String { self.name }
    
    public var keyPath: String {
        switch self {
        case .subsystem:
            return "subsystem"
        case .category:
            return "category"
        case .message:
            return "message"
        case .process:
            return "process"
        case .pid:
            return "processIdentifier"
        case .sender:
            return "sender"
        case .activity:
            return "activityIdentifierValue"
        case .thread:
            return "threadIdentifier"
        }
    }
}

extension PropertyQuery.Comparison : Identifiable {
    public var id: Int { self.rawValue }
    
    public var symbol: String {
        switch self {
        case .contains:         "≈"
        case .equals:           "="
        case .doesNotContain:   "≉"
        case .doesNotEqual:     "≠"
        }
    }
    
    public var analyticsSymbol: String {
        switch self {
        case .contains:         "~="
        case .equals:           "=="
        case .doesNotContain:   "!~"
        case .doesNotEqual:     "!="
        }
    }
}

// MARK: - Evaluation

extension PropertyQuery {
    
    func evaluate(_ entry: Entry, _ context: FilterContext) -> Bool {
        let comparisonString: String?
        switch self.property {
        case .subsystem:
            comparisonString = entry.subsystem
        case .category:
            comparisonString = entry.category
        case .message:
            comparisonString = entry.message
        case .process:
            comparisonString = entry.process
        case .pid:
            comparisonString = "\(entry.processIdentifier)"
        case .sender:
            comparisonString = entry.sender
        case .activity:
            comparisonString = "\(entry.activityIdentifier)"
        case .thread:
            comparisonString = String(format: "0x%02x", entry.threadIdentifier)
        }
        
        guard let comparisonString else {
            // We don't have anyting to compare to.
            // This is special for the "does not equal/contain" cases.
            switch self.comparison {
            case .doesNotEqual, .doesNotContain:
                return true
            case .contains, .equals:
                return false
            }
        }
        
        // If the user hasn't typed anything yet, then we pretend like it matches.
        if self.value == "" { return true }
        
        // We passed all our special conditions. Let's do the comparison!
        // Looks like NSString is about a trajillion times faster than Swift String.
        let nsString = comparisonString as NSString
        
        switch self.comparison {
        case .contains:
            return nsString.range(of: self.value, options: [.caseInsensitive, .diacriticInsensitive]).location != NSNotFound
        case .equals:
            return nsString.isEqual(to: self.value)
        case .doesNotEqual:
            return !nsString.isEqual(to: self.value)
        case .doesNotContain:
            return nsString.range(of: self.value, options: [.caseInsensitive, .diacriticInsensitive]).location == NSNotFound
        }
    }
}

// MARK: - Description

extension PropertyQuery : CustomStringConvertible {
    
    public var description: String {
        return "(\(self.property.name) \(self.comparison.symbol) '\(self.value)')"
    }
    
    public var predicateString: String {
        switch self.comparison {
        case .contains:
            return "(\(self.property.logPredicateKeyPath) CONTAINS[cd] '\(self.value)')"
        case .equals:
            return "(\(self.property.logPredicateKeyPath) == '\(self.value)')"
        case .doesNotContain:
            return "!(\(self.property.logPredicateKeyPath) CONTAINS[cd] '\(self.value)')"
        case .doesNotEqual:
            return "(\(self.property.logPredicateKeyPath) != '\(self.value)')"
        }
    }
}
