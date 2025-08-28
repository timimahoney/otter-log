//
//  SavedQueries.swift
//  Otter
//
//  Created by Tim Mahoney on 1/13/24.
//

import Foundation
import SwiftUI

@Observable public class SavedQueries {
    
    static let defaultsKey = "OTUserSavedQueries"
    
    public private(set) var savedQueries: [UserQuery]
    
    var defaults: UserDefaults
    
    public init(defaults: UserDefaults = UserDefaults.standard, defaultQueries: [UserQuery]? = nil) {
        let queriesToRegister = defaultQueries ?? Self.defaultQueries
        Self.registerDefaultQueries(defaults, queries: queriesToRegister)
        self.defaults = defaults
        do {
            self.savedQueries = try Self.loadQueries(from: defaults)
        } catch {
            Logger.savedQueries.fault("Failed to load persisted queries. Falling back to default: \(error)")
            self.savedQueries = Self.defaultQueries
        }
    }
    
    // MARK: - Mutation
    
    public func save(_ query: UserQuery) {
        // ...should we actually be deduplicating the name here? Or elsewhere?
        if let matchingName = self.queryNamed(query.name) {
            self.savedQueries.replace([matchingName], with: [query])
        } else if let sameQuery = self.queryWithID(query.id) {
            self.savedQueries.replace([sameQuery], with: [query])
        } else {
            self.savedQueries.append(query)
        }
        do {
            try Self.persistQueries(self.savedQueries, to: self.defaults)
        } catch {
            Logger.savedQueries.fault("Failed to persist queries when saving query: \(error)")
        }
    }
    
    public func remove(_ query: UserQuery) {
        self.savedQueries.removeAll { $0 == query }
        do {
            try Self.persistQueries(self.savedQueries, to: self.defaults)
        } catch {
            Logger.savedQueries.fault("Failed to persist queries when removing query: \(error)")
        }
    }
    
    // MARK: - Query Getters
    
    public func queryMatching(_ query: UserQuery) -> UserQuery? {
        // Let's check if we have an existing query that looks just like this one.
        // We need to do a dance around our unique ID property and the name.
        return self.savedQueries.first { existingQuery in
            var queryToCompare = existingQuery
            queryToCompare.id = query.id
            queryToCompare.name = query.name
            return queryToCompare == query
        }
    }
    
    public func queryWithID(_ id: UserQuery.ID) -> UserQuery? {
        return self.savedQueries.first { $0.id == id }
    }
    
    
    public func queryNamed(_ name: String) -> UserQuery? {
        return self.savedQueries.first { $0.name == name }
    }
    
    // MARK: - Persistence
    
    static func registerDefaultQueries(_ defaults: UserDefaults, queries: [UserQuery]) {
        do {
            let serialized = try Self.serializedQueries(queries)
            defaults.register(defaults: [Self.defaultsKey : serialized])
        } catch {
            Logger.savedQueries.fault("Unable to serialize queries to register defaults: \(error)")
        }
    }
    
    static func loadQueries(from defaults: UserDefaults) throws -> [UserQuery] {
        if let data = defaults.data(forKey: Self.defaultsKey) {
            return try JSONDecoder().decode([UserQuery].self, from: data)
        } else {
            return Self.defaultQueries
        }
    }
    
    static func serializedQueries(_ queries: [UserQuery]) throws -> Data {
        return try JSONEncoder().encode(queries)
    }
    
    static func persistQueries(_ queries: [UserQuery], to defaults: UserDefaults) throws {
        let data = try Self.serializedQueries(queries)
        defaults.set(data, forKey: Self.defaultsKey)
    }
    
    func reset() {
        self.defaults.removeObject(forKey: Self.defaultsKey)
        self.savedQueries = Self.defaultQueries
    }
    
    // MARK: - Default Queries
    
    static func previewQueries() -> SavedQueries {
        let queries = self.defaultQueries + self.defaultQueries + self.defaultQueries + self.defaultQueries
        let defaults = UserDefaults.init(suiteName: "com.jollycode.otter.preview")!
        return SavedQueries(defaults: defaults, defaultQueries: queries)
    }
    
    private static let defaultQueries: [UserQuery] = {
        return [
            UserQuery(
                name: "Errors and Faults",
                topLevelQuery: .and([
                    .contains(.process),
                    .contains(.message),
                    .logLevel([ .error, .fault ]),
                ]),
                colorizations: [
                    Colorization(query: .or([
                        .logLevel([ .fault ])
                    ]),  color: .red),
                ]
            ),
            
            // Lots of subqueries
            UserQuery(
                name: "CloudKit Operations",
                topLevelQuery: .and([
                    .contains(.process),
                    .contains(.message),
                    .equals(.subsystem, "com.apple.cloudkit"),
                    .contains(.category, "OP"),
                    .doesNotEqual(.process, "cloudd"),
                ]),
                colorizations: [
                    Colorization(query: .or([ .contains(.message, "Starting operation") ]), color: .gray),
                    Colorization(query: .and([ .contains(.message, "Finished operation"), .contains(.message, "error") ]), color: .red),
                    Colorization(query: .or([ .contains(.message, "Finished operation") ]), color: .green),
                ]
            ),
            
            // Lots of subqueries
            UserQuery(
                name: "CKSyncEngine",
                topLevelQuery: .and([
                    .contains(.process),
                    .contains(.message),
                    .logLevel([.error, .fault, .notice]),
                    .equals(.subsystem, "com.apple.cloudkit"),
                    .or([
                        .equals(.category, "Engine"),
                        .equals(.category, "Scheduler"),
                        .equals(.category, "NotificationListener"),
                    ])
                ]),
                colorizations: [
                    Colorization(query: .or([ .contains(.category, "NotificationListener") ]), color: .purple),
                    Colorization(query: .or([ .contains(.category, "Scheduler") ]), color: .indigo),
                    Colorization(query: .or([ .contains(.message, "will post event: <Fetch") ]), color: .blue),
                    Colorization(query: .or([ .contains(.message, "will post event: <Sent") ]), color: .green),
                    Colorization(query: .or([ .contains(.message, "will post event: <Account") ]), color: .yellow),
                    Colorization(query: .or([ .logLevel([.error, .fault]) ]), color: .red),
                    Colorization(query: .or([
                        .contains(.message, "initialized sync engine"),
                        .contains(.message, "deallocating sync engine"),
                    ]), color: .darkGray),
                    Colorization(query: .or([ .contains(.message, "CKSyncEngine.State") ]), color: .gray),
                ]
            ),
            
            // Lots of subqueries
            UserQuery(
                name: "NSUbiquitousKeyValueStore",
                topLevelQuery: .and([
                    .contains(.process),
                    .equals(.subsystem, "com.apple.kvs"),
                    .doesNotEqual(.process, "syncdefaultsd"),
                    .or([
                        .contains(.message, "Returning object for key"),
                        .contains(.message, "Setting object for key"),
                        .logLevel([.error, .fault])
                    ])
                ]),
                colorizations: [
                    Colorization(query: .or([ .contains(.message, "Returning object for key") ]), color: .blue),
                    Colorization(query: .or([ .contains(.message, "Setting object for key") ]), color: .green),
                    Colorization(query: .or([ .logLevel([.error, .fault]) ]), color: .red),
                ]
            ),
            
            /*
             TODO: More saved queries?
            UserQuery(
                name: "Sandbox",
                topLevelQuery: .and([
                    .or([
                        .equals(.subsystem, "sandbox"),
                        .contains(.message, "sandbox"),
                    ]),
                    .or([
                        .contains(.message),
                        .contains(.process),
                    ]),
                ])
            ),
             */
        ]
    }()
}
