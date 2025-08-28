//
//  UserQuery.swift
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

import Foundation
import OSLog
import SwiftUI

public struct UserQuery : Identifiable, Codable, Hashable, Sendable {
    
    public var id = Int.random(in: Int.min..<Int.max)
    
    public var name: String = ""
    
    public var topLevelQuery: Subquery
    
    public var colorizations: [Colorization] = []
    
    public init(
        name: String = "",
        topLevelQuery: Subquery = .defaultQuery,
        colorizations: [Colorization] = Subquery.defaultColorizations
    ) {
        self.name = name
        self.topLevelQuery = topLevelQuery
        self.colorizations = colorizations
    }
    
    public mutating func assignNewIDs() {
        self.id = Int.random(in: Int.min..<Int.max)
        self.topLevelQuery.assignNewIDs()
    }
}

// MARK: - Other

extension UserQuery : CustomStringConvertible {
    
    public var description: String {
        return "UserQuery(name:\(self.name), id: \(self.id), query: \(self.topLevelQuery))"
    }
}
