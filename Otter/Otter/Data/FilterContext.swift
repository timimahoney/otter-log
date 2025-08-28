//
//  FilterContext.swift
//  Otter
//
//  Created by Tim Mahoney on 2/1/24.
//

import Foundation

/// An object representing a single attempt by the user to filter some log entries.
/// You can use this to pass along things that might be shared amongst all queries.
///
/// The lifecycle of a `FilterContext` starts at the beginning of a single user query, and ends when that query is finished.
/// It should not live across multiple queries by the user.
final public class FilterContext : Sendable {
    
    public init() {
        
    }
}
