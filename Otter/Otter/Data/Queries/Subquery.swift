//
//  Subquery.swift
//  Otter
//
//  Created by Tim Mahoney on 2/1/24.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

public enum Subquery : Codable, Hashable, Sendable {
    
    case compound(CompoundQuery)
    case property(PropertyQuery)
    case logLevel(LogLevelQuery)
}

extension Subquery : Identifiable {
    
    public var id: UUID {
        switch self {
        case .compound(let compound): compound.id
        case .property(let property): property.id
        case .logLevel(let logLevel): logLevel.id
        }
    }
    
    // DANGEROUS!
    // Only use this if you know the proper query type
    // TODO: Clean this up? Put them into the enum?
    var compoundQuery: CompoundQuery {
        get {
            if case let .compound(compound) = self {
                return compound
            } else {
                fatalError("Tried to access a compound query from a non-compound query: \(self)")
            }
        }
        set {
            self = .compound(newValue)
        }
    }
    
    var propertyQuery: PropertyQuery {
        get {
            if case let .property(property) = self {
                return property
            } else {
                fatalError("Tried to access a property query from a non-property query: \(self)")
            }
        }
        set {
            self = .property(newValue)
        }
    }
    
    var logLevelQuery: LogLevelQuery {
        get {
            if case let .logLevel(property) = self {
                return property
            } else {
                fatalError("Tried to access a property query from a non-property query: \(self)")
            }
        }
        set {
            self = .logLevel(newValue)
        }
    }
    
    public var isEmpty: Bool {
        switch self {
        case .property(let property):
            return property.value.isEmpty
        case .compound(let compound):
            return !compound.subqueries.contains { !$0.isEmpty }
        case .logLevel(let logLevel):
            return logLevel.logLevels.isEmpty
        }
    }
    
    /// Returns a new query that is functionally the same as this query, but optimized for faster calculation.
    /// If this query is essentially empty (e.g. a property comparison to nothing, th
    public func optimized() -> Subquery? {
        switch self {
        case .property, .logLevel:
            return self.isEmpty ? nil : self
        case .compound(var compound):
            let nonEmptySubqueries = compound.subqueries.compactMap { $0.optimized() }
            if nonEmptySubqueries.isEmpty {
                return nil
            } else if nonEmptySubqueries.count == 1 {
                return nonEmptySubqueries.first
            } else {
                compound.subqueries = nonEmptySubqueries
                return .compound(compound)
            }
        }
    }
    
    public var firstEmptyQuery: Subquery? {
        switch self {
        case .property(let property):
            if property.value.isEmpty {
                return self
            }
        case .compound(let compound):
            for subquery in compound.subqueries {
                if let firstEmptyQuery = subquery.firstEmptyQuery {
                    return firstEmptyQuery
                }
            }
        case .logLevel:
            return nil
        }
        return nil
    }
    
    public mutating func assignNewIDs() {
        switch self {
        case .property(var property):
            property.id = UUID()
            self = .property(property)
        case .compound(var compound):
            compound.id = UUID()
            compound.subqueries = compound.subqueries.map {
                var subquery = $0
                subquery.assignNewIDs()
                return subquery
            }
            self = .compound(compound)
        case .logLevel(var logLevel):
            logLevel.id = UUID()
            self = .logLevel(logLevel)
        }
    }
    
    /// Returns a list of this query and all its subqueries, recursively.
    public var recursiveQueries: [Subquery] {
        var queries = [self]
        switch self {
        case .property, .logLevel:
            break
        case .compound(let compound):
            let recursiveSubqueries = compound.subqueries.flatMap { $0.recursiveQueries }
            queries.append(contentsOf: recursiveSubqueries)
        }
        return queries
    }
}

extension Subquery : CustomStringConvertible {
    
    public var description: String { self.predicateString }
    
    public var predicateString: String {
        switch self {
        case .property(let property):
            return property.predicateString
        case .compound(let compound):
            return compound.predicateString
        case .logLevel(let logLevel):
            return logLevel.predicateString
        }
    }
}

// MARK: - Helper Initializers

extension Subquery {
    
    public static func and(_ subqueries: [Subquery]) -> Subquery {
        return .compound(.and(subqueries))
    }
    
    public static func or(_ subqueries: [Subquery]) -> Subquery {
        return .compound(.or(subqueries))
    }
    
    public static func contains(_ property: PropertyQuery.Property, _ value: String = "") -> Subquery {
        return .property(.contains(property, value))
    }
    
    public static func equals(_ property: PropertyQuery.Property, _ value: String = "") -> Subquery {
        return .property(.equals(property, value))
    }
    
    public static func doesNotContain(_ property: PropertyQuery.Property, _ value: String = "") -> Subquery {
        return .property(.doesNotContain(property, value))
    }
    
    public static func doesNotEqual(_ property: PropertyQuery.Property, _ value: String = "") -> Subquery {
        return .property(.doesNotEqual(property, value))
    }
    
    public static func logLevel(_ selectedLevels: [OSLogEntryLog.Level] = []) -> Subquery {
        let levelValues = selectedLevels.map { $0.rawValue }
        return .logLevel(.init(logLevelValues: Set(levelValues)))
    }
    
    public static var defaultQuery: Subquery {
        .and([
            .logLevel(),
            .contains(.subsystem),
            .contains(.process),
            .or([
                .contains(.message),
                .contains(.message)
            ])
        ])
    }
    
    public static var defaultColorizations: [Colorization] {
        return [
            Colorization(query: .or([.contains(.category)]), color: .orange),
            Colorization(query: .or([.contains(.message)]), color: .yellow),
        ]
    }
    
    public static var defaultColorizeQuery: Subquery {
        .and([
            .contains(.message),
        ])
    }
}

// MARK: - Evaluation

extension Subquery {
    
    public func evaluate(_ entry: Entry, _ context: FilterContext) -> Bool {
        switch self {
        case .property(let property):
            return property.evaluate(entry, context)
        case .compound(let compound):
            return compound.evaluate(entry, context)
        case .logLevel(let logLevel):
            return logLevel.evaluate(entry, context)
        }
    }
}

// MARK: - Transferable

extension Subquery : Transferable {
    
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .subquery)
        ProxyRepresentation(exporting: { $0.optimized()?.predicateString ?? $0.predicateString })
    }
}

extension UTType {
    
    static var subquery: UTType { UTType(exportedAs: "com.jollycode.otter.subquery") }
}
