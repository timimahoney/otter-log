//
//  InspectorStats.swift
//  Otter
//
//  Created by Tim Mahoney on 2/16/24.
//

import Foundation

struct InspectorStats : Sendable {
    
    static let statCountContractedGlobal = 16
    static let statCountExpandLimitGlobal = 24
    static let statCountContractedPerProcess = 5
    static let statCountExpandLimitPerProcess = 10
    
    var processStats: StatSection = .init(
        name: .otter_processes, stats: [],
        expandLimit: Self.statCountExpandLimitGlobal,
        contractedCount: Self.statCountContractedGlobal
    )
    
    var subsystemStats: StatSection = .init(
        name: .otter_subsystems,
        stats: [],
        expandLimit: Self.statCountExpandLimitGlobal,
        contractedCount: Self.statCountContractedGlobal
    )
    
    var activityStats: StatSection = .init(
        name: .otter_activities,
        stats: [],
        expandLimit: Self.statCountExpandLimitGlobal,
        contractedCount: Self.statCountContractedGlobal
    )
    
    var perProcessStats: [ProcessStatSection] = []
}

public struct ProcessStatSection : Identifiable, Hashable, Sendable {
    var process: String
    var count: Int
    
    var subsystemStats: StatSection
    var activityStats: StatSection
    
    public var id: String { self.process }
}

public struct StatSection : Identifiable, Hashable, Sendable {
    public let name: String
    public var parentSection: String? = nil
    public var stats: [Stat]
    
    /// In order to avoid things like "1 more…", we have both an "expand limit" and a "contracted count".
    /// `expandLimit` is the number of items necessary before we show the "show more" button.
    /// `contractedCount` is the number of items we show if we're showing the "show more" button.
    /// The expand limit should be larger than the contracted count.
    var expandLimit: Int
    var contractedCount: Int
    
    var showSectionName: Bool = true
    
    var isExpandedKey: String { "::--::--OTTER-\((self.parentSection ?? "") + self.name)" }
    public var id: String { self.isExpandedKey }
    
    public func hash(into hasher: inout Hasher) {
        self.id.hash(into: &hasher)
        self.stats.count.hash(into: &hasher)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id && lhs.stats.count == rhs.stats.count
    }
}

public struct Stat : Identifiable, Sendable {
    public let name: String
    public let value: Int
    
    public var id: String { self.name }
}
