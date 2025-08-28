//
//  CompoundQuery.swift
//  Otter
//
//  Created by Tim Mahoney on 2/1/24.
//

import Foundation
import SwiftUI

public struct CompoundQuery : Codable, Hashable, Sendable {
    
    var id: UUID = UUID()
    
    public enum Variant : Codable, Hashable, Identifiable, CaseIterable, Sendable {
        case and
        case or
        
        public var id: String { String(describing: self) }
    }
    
    public var variant: Variant = .and
    
    public var subqueries: [Subquery] = []
}

extension CompoundQuery {
    
    mutating func addSubquery(_ subquery: Subquery) {
        self.subqueries.append(subquery)
    }
    
    mutating func removeSubquery(_ subquery: Subquery) {
        self.subqueries.removeAll { $0.id == subquery.id }
    }
    
    /// Finds the parent of the given subquery within this compound query tree.
    /// If no parent was found, this returns nil.
    /// If `self` is the parent, then this returns `self`.
    func parent(of subquery: Subquery) -> CompoundQuery? {
        for child in self.subqueries {
            if child == subquery {
                return self
            } else {
                switch child {
                case .compound:
                    let possibleParentFromChild = self.parent(of: subquery)
                    if let possibleParentFromChild {
                        return possibleParentFromChild
                    }
                case .property, .logLevel:
                    break
                }
            }
        }
        
        return nil
    }
    
    mutating func move(_ subqueries: [Subquery], before other: Subquery) {
        self.move(subqueries, nextTo: other, offset: 0)
    }
    
    mutating func move(_ subqueries: [Subquery], after other: Subquery) {
        self.move(subqueries, nextTo: other, offset: 1)
    }
    
    mutating private func move(_ subqueries: [Subquery], nextTo other: Subquery, offset: Int) {
        
        // We might be moving subqueries from completely unrelated parts of the query graph.
        // To make things simple, let's just do this:
        // 1. Remove any of the new subqueries from self.
        // 2. Recursively move the new subqueries within our own subqueries.
        // 3. Insert the new subqueries into self if necessary.
        
        // Check if we're going to move the new subqueries into self.
        // Do this before removing the subqueries from self because `other` might be in `subqueries`.
        
        // 1. Remove any of the new subqueries from self.
        self.subqueries.removeAll { other != $0 && subqueries.contains($0) }
        
        // 2. Recursively move the new subqueries within our own subqueries.
        self.subqueries = self.subqueries.map { child in
            switch child {
            case .compound:
                var newChild = child
                newChild.compoundQuery.move(subqueries, nextTo: other, offset: offset)
                return newChild
            case .property, .logLevel:
                return child
            }
        }
        
        // 3. Insert the new subqueries into self if necessary.
        // Check the ID of the subqueries instead of `==` because the subqueries might have changed.
        let targetIndex = self.subqueries.firstIndex { $0.id == other.id }
        if let targetIndex {
            if subqueries.contains(other) {
                self.subqueries.removeAll { $0 == other }
            }
            let desiredIndex = min(targetIndex + offset, self.subqueries.count)
            self.subqueries.insert(contentsOf: subqueries, at: desiredIndex)
        }
    }
    
    /// Returns true `self` is equal to `other` or if `other` is contained within `self`, recursively.
    func isOrContains(_ other: CompoundQuery) -> Bool {
        if other == self {
            return true
        }
        
        for subquery in self.subqueries {
            if case let .compound(compound) = subquery {
                if compound.isOrContains(other) {
                    return true
                }
            }
        }
        
        return false
    }
}

extension CompoundQuery.Variant {
    
    var symbolLocalized: LocalizedStringKey {
        switch self {
        case .and: "&&"
        case .or:  "||"
        }
    }
    
    var symbol: String {
        switch self {
        case .and: "&&"
        case .or:  "||"
        }
    }
    
    var compoundPredicateType: NSCompoundPredicate.LogicalType {
        switch self {
        case .and: .and
        case .or: .or
        }
    }
}

// MARK: - Initialization Helpers

extension CompoundQuery {
    
    public static func and(_ subqueries: [Subquery]) -> CompoundQuery {
        return CompoundQuery(variant: .and, subqueries: subqueries)
    }
    
    public static func or(_ subqueries: [Subquery]) -> CompoundQuery {
        return CompoundQuery(variant: .or, subqueries: subqueries)
    }
}

// MARK: - Description

extension CompoundQuery : CustomStringConvertible {
    
    public var description: String {
        let subqueryDescriptions = self.subqueries.map { $0.description }.joined(separator: " \(self.variant.symbol) ")
        return "(\(subqueryDescriptions))"
    }
    
    public var predicateString: String {
        let subqueryPredicates = self.subqueries.map { $0.predicateString }.joined(separator: " \(self.variant.symbol) ")
        return "(\(subqueryPredicates))"
    }
}

// MARK: - Evaluation

extension CompoundQuery {
    
    func evaluate(_ entry: Entry, _ context: FilterContext) -> Bool {
        let subqueries = self.subqueries
        if subqueries.isEmpty {
            return true
        }
        
        switch self.variant {
        case .and:
            let count = subqueries.count
            for i in 0..<count {
                let subquery = subqueries[i]
                if !subquery.evaluate(entry, context) {
                    return false
                }
            }
            return true
        case .or:
            let count = subqueries.count
            for i in 0..<count {
                let subquery = subqueries[i]
                if subquery.evaluate(entry, context) {
                    return true
                }
            }
            return false
        }
    }
}
