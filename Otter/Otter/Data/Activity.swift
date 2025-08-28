//
//  Activity.swift
//  Otter
//
//  Created by Tim Mahoney on 1/7/24.
//

import Foundation
import OSLog

public struct Activity : Identifiable, Codable, Sendable {
    
    public var id: os_activity_id_t
    public var parentID: Activity.ID?
    
    public var name: String
    public var process: String
    public var date: Date
    
    public var subactivities: [Activity]?
    public var subactivityIDs: [Activity.ID] = []
    
    /// The IDs of all the subactivities, recursively including all subactivities, not including self.
    public var recursiveSubactivityIDs: [ID] {
        return self.recursiveSubactivities.map { $0.id }
    }
    
    /// The IDs of all the subactivities, recursively including all subactivities, including self.
    public var recursiveSubactivityIDsIncludingSelf: [ID] {
        return self.recursiveSubactivitiesIncludingSelf.map { $0.id }
    }
    
    /// Returns all the activities in the tree of subactivities, not including self.
    public var recursiveSubactivities: [Activity] {
        return self.subactivities?.reduce(into: []) {
            $0.append($1)
            $0.append(contentsOf: $1.recursiveSubactivities)
        } ?? []
    }
    
    /// Returns all the activities in the tree of subactivities, including self at the beginning.
    public var recursiveSubactivitiesIncludingSelf: [Activity] {
        return [self] + self.recursiveSubactivities
    }

}

extension Activity {
    
    static func fromEntries(_ entries: [Entry]) -> [Activity] {
        var activityIDsInOrder: [Activity.ID] = []
        var activitiesByID: [Activity.ID : Activity] = [:]
        
        // At the end, we want to return the hierarchy of activites.
        // We don't want to return child activities at the top level.
        // Keep track of the activities that we know are top-level activities.
        var topLevelActivityIDsInOrder: [Activity.ID] = []
        
        // Get all the activity entries.
        let activityEntries = entries.filter { $0.type == .activity }
        
        // Construct a list of activities in order, properly constructing their subactivity ID lists.
        for entry in activityEntries {
            let activityID = entry.activityIdentifier
            let activity = Activity(id: activityID, parentID: entry.parentActivityIdentifier, name: entry.message, process: entry.process, date: entry.date)
            activityIDsInOrder.append(activityID)
            activitiesByID[activityID] = activity
            
            if let parentActivityID = entry.parentActivityIdentifier {
                if var parentActivity = activitiesByID[parentActivityID] {
                    parentActivity.subactivityIDs.append(activityID)
                    activitiesByID[parentActivityID] = parentActivity
                } else {
                    topLevelActivityIDsInOrder.append(activityID)
                }
            }
        }
        
        // Now finally assemble the tree of activities.
        // Note that this is a bit tricky due to the use of value types.
        // When we set the subactivity array on an activity,
        // we need to make sure all the subactivity arrays of those subactivities are already fully materialized.
        // In order to do this, let's start from the end and work backwards.
        for id in activityIDsInOrder.reversed() {
            guard var activity = activitiesByID[id] else {
                Logger.data.fault("Couldn't find activity for id \(id)")
                continue
            }
            if !activity.subactivityIDs.isEmpty {
                let subactivities = activity.subactivityIDs.compactMap { activitiesByID[$0] }
                activity.subactivities = subactivities
                activitiesByID[id] = activity
            }
        }
        
        return topLevelActivityIDsInOrder.compactMap { activitiesByID[$0] }
    }
}

// MARK: - Hashable / Equatable

// Implement this in a more efficient way to speed up SwiftUI.
extension Activity : Hashable {
    
    public func hash(into hasher: inout Hasher) {
        self.id.hash(into: &hasher)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
}
