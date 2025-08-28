//
//  QueryView.swift
//  Otter
//
//  Created by Tim Mahoney on 2/5/24.
//

import Foundation
import SwiftUI

struct QueryView : View {
    
    @Binding var query: Subquery
    @Binding var parent: CompoundQuery
    @Binding var topLevelQuery: CompoundQuery
    @FocusState var focusedSubquery: Subquery?
    var compact: Bool = false
    var delete: (() -> ())?
    
    @State var isTargetedLeft = false
    @State var isTargetedRight = false
    
    static let strokeWidth: CGFloat = 1
    
    static let selectionWidth: CGFloat = 6
    static let selectionPadding: CGFloat = 2
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 0) {
            if self.isTargetedLeft {
                DropTargetView()
                    .padding([.trailing], QueryView.selectionPadding * 2)
            }
            
            switch self.query {
            case .compound:
                CompoundQueryView(query: self.$query.compoundQuery, topLevelQuery:self.$topLevelQuery, color: .constant(.red), compact: self.compact, delete: self.delete)
                    .draggable(self.query)
            case .property:
                PropertyQueryView(query: self.$query.propertyQuery, compact: self.compact, delete: self.delete)
                    .focused(self.$focusedSubquery, equals: self.query)
                    .draggable(self.query)
            case .logLevel:
                LogLevelQueryView(query: self.$query.logLevelQuery, compact: self.compact, delete: self.delete)
                    .draggable(self.query)
            }
            
            if self.isTargetedRight {
                DropTargetView()
                    .padding([.leading], QueryView.selectionPadding * 2)
            }
        }
        .padding([.leading], 2)
        .padding([.trailing], 2)
        .onDrop(of: [.subquery], delegate: self)
    }
}

struct DropTargetView : View {
    
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(NSColor(Color.accentColor).blended(withFraction: 0.3, of: NSColor.white)!))
            .frame(width: QueryView.selectionWidth)
            .frame(height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.accentColor)
            )
    }
}

// MARK: DropDelegate

extension QueryView : DropDelegate {
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.subquery])
    }
    
    func dropEntered(info: DropInfo) {
        self.updateIsTargeted(info: info)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        self.updateIsTargeted(info: info)
        return DropProposal(operation: .move)
    }
    
    func dropExited(info: DropInfo) {
        withAnimation(.otter) {
            self.isTargetedLeft = false
            self.isTargetedRight = false
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let targetedLeft = self.isTargetedLeft
        let targetedRight = self.isTargetedRight
        guard targetedLeft || targetedRight else { return false }
        
        // We want to get the subqueries in order, and ItemProvider is async/await.
        // We have to do some gymnastics to get the right order later.
        let subqueriesLock = OSAllocatedUnfairLock<[Int : Subquery]>(initialState: [:])
        let group = DispatchGroup()
        let itemProviders = info.itemProviders(for: [.subquery])
        for (i, provider) in itemProviders.enumerated() {
            group.enter()
            // TODO: Progress?
            _ = provider.loadTransferable(type: Subquery.self) { result in
                switch result {
                case .success(let subquery):
                    subqueriesLock.withLock { $0[i] = subquery }
                case .failure(let error):
                    Logger.ui.error("Failed to load Subquery when dropping: \(error)")
                }
                group.leave()
            }
        }
        
        group.wait()
        
        // Finally, we did some backflips around the async item provider fun.
        // Let's move our subqueries to the right place.
        // Note that we have to use the top level query here.
        // We might be moving to a parent that isn't our own parent.
        let subqueries: [Subquery] = info.transferrables(for: .subquery)
        withAnimation(.otter) {
            if subqueries == [self.query] {
                // We're dropping a single query on ourselves. Do nothing.
                // This might not work generically, but it fixes the issue I can find.
            } else {
                // Check if the user is trying to drop a subquery within itself.
                let isDroppingWithinSelf = subqueries.contains {
                    if case let .compound(compound) = $0, compound.isOrContains(self.parent) {
                        return true
                    }
                    return false
                }
                if !isDroppingWithinSelf {
                    if targetedLeft {
                        self.topLevelQuery.move(subqueries, before: self.query)
                    } else if targetedRight {
                        self.topLevelQuery.move(subqueries, after: self.query)
                    }
                }
            }
            
            self.isTargetedLeft = false
            self.isTargetedRight = false
        }
        
        return true
    }
    
    func updateIsTargeted(info: DropInfo) {
        // An estimate of half the width of a property view.
        // If we're less than that, the left is targeted.
        // Otherwise, pretend like we know that the right is targeted.
        // We always want to animate the fade away of the cursor.
        let isLeftTargeted = (info.location.x < 72)
        withAnimation(.otter) {
            self.isTargetedLeft = isLeftTargeted
            self.isTargetedRight = !isLeftTargeted
        }
    }
}
