//
//  Logger+Otter.swift
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

import os.log

extension Logger {
    
    static let subsystem = "com.jollycode.otter"
    
    static let ui = Logger(subsystem: Self.subsystem, category: "UI")
    static let find = Logger(subsystem: Self.subsystem, category: "Find")
    static let data = Logger(subsystem: Self.subsystem, category: "Data")
    static let filteredData = Logger(subsystem: Self.subsystem, category: "FilteredData")
    static let savedQueries = Logger(subsystem: Self.subsystem, category: "SavedQueries")
    static let analytics = Logger(subsystem: Self.subsystem, category: "Analytics")
}
