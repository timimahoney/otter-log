//
//  QuerySectionView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/22/24.
//

import Foundation
import SwiftUI

struct QuerySectionView : View {

    @Environment(SavedQueries.self) var savedQueries
    
    @Binding var query: UserQuery
    
    @FocusState var focusedSubquery: Subquery?
    
    @State private var isShowingSaveAlert: Bool = false
    @State private var savedQueryName: String = ""
    
    @State private var isShowingDuplicateAlert: Bool = false
    @State private var duplicateQueryName: String = ""
    
    @State private var isShowingReplaceAlert: Bool = false
    
    @State private var colorizationChangeCoalescer = Coalescer()
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 0) {
            
            //
            // Saved queries
            //
            HStack(spacing: 4) {
                
                //
                // Reset Filter button
                //
                Button("Reset Filter") {
                    let query = UserQuery(name: String(localized: "New Filter"))
                    // TODO: Re-enable animations. For now, they're causing crashes.
//                    withAnimation(.otter) {
                        self.query = query
                        self.focusedSubquery = query.topLevelQuery.firstEmptyQuery
//                    }
                    
                    Analytics.track("Reset Filter", self.query.topLevelQuery.analyticsProperties)
                }
                .buttonStyle(.accessoryBarAction)
                .foregroundStyle(.tertiary)
                
                Button("Save Filter") {
                    self.savedQueryName = self.query.name
                    self.isShowingSaveAlert = true
                    
                    Analytics.track("Save Filter", self.query.topLevelQuery.analyticsProperties)
                }
                .buttonStyle(.accessoryBarAction)
                
                //
                // Saved queries
                //
                SavedQueriesView(isShowingSaveAlert: self.$isShowingSaveAlert) { selectedQuery in
                    // TODO: Animate this, bruh.
//                    withAnimation(.otter) {
                        self.query = selectedQuery
                        self.focusedSubquery = selectedQuery.topLevelQuery.firstEmptyQuery
//                    }
                    
                    Analytics.track("Select Saved Query", selectedQuery.topLevelQuery.analyticsProperties)
                }
                .environment(self.savedQueries)
            }
            .padding(4)
            .padding(.top, 2)
            
            //
            // User query
            //
            ScrollView(.horizontal) {
                CompoundQueryView(
                    query: self.$query.topLevelQuery.compoundQuery,
                    topLevelQuery: self.$query.topLevelQuery.compoundQuery,
                    color: .constant(.red),
                    focusedSubquery: _focusedSubquery
                )
                .padding([.leading, .trailing], 4)
                .padding(.bottom, 4)
            }
            
            Divider()
            
            //
            // Colorizations
            //
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: 4) {
                    Button {
                        withAnimation(.otter) {
                            self.addNewColorization()
                        }
                        
                        let properties = self.query.topLevelQuery.analyticsProperties
                        Analytics.track("Add Colorization", properties)
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .frame(width: 30, height: 29)
                            .font(.headline)
                            .fontWeight(.black)
                    }
                    .buttonStyle(ColorizeButtonStyle())
                    .foregroundStyle(.tertiary)
                    
                    ForEach(self.$query.colorizations) { $colorizeQuery in
                        CompoundQueryView(
                            query: $colorizeQuery.query.compoundQuery,
                            topLevelQuery: $colorizeQuery.query.compoundQuery,
                            color: $colorizeQuery.color,
                            showColorPicker: true,
                            focusedSubquery: _focusedSubquery,
                            compact: true
                        ) {
                            withAnimation(.otter) {
                                self.query.colorizations.removeAll { $0.id == colorizeQuery.id }
                            }
                        }
                        .draggable(colorizeQuery.query)
                    }
                }
                .padding([.top, .bottom], 4)
                .padding([.leading, .trailing], 4)
            }
        }
        .onChange(of: self.query.colorizations) { oldValue, newValue in
            self.colorizationChangeCoalescer.coalesce(delay: 1) {
                let rawQuery = Subquery.or(newValue.map { $0.query })
                let queryString = rawQuery.optimized()?.analyticsStructure ?? ""
                Analytics.track("Changed Colorizations", [
                    .analytics_colorizationCount : newValue.count,
                    .analytics_queryStructureOptimized : queryString,
                ])
            }
        }
        .alert(
            "Save Filter",
            isPresented: self.$isShowingSaveAlert,
            actions: {
                TextField("Filter name", text: self.$savedQueryName)
                Button("Save") {
                    self.query.name = self.savedQueryName
                    self.saveQuery(checkDuplicate: true, checkName: true, event: "Save Filter")
                }
                .disabled(self.savedQueryName.isEmpty)
                Button("Cancel", role: .cancel) { /* Nothing... */ }
            },
            message: {
                Text("Enter a name for your saved filter.")
            }
        )
        .alert(
            "Filter named “\(self.savedQueryName)” already exists. Do you want to replace it?",
            isPresented: self.$isShowingReplaceAlert,
            actions: {
                Button("Save") {
                    self.query.name = self.savedQueryName
                    self.saveQuery(checkDuplicate: true, checkName: false, event: "Replace Existing Filter")
                    
                    Analytics.track("Replace Filter", self.query.topLevelQuery.analyticsProperties)
                }
                Button("Cancel", role: .cancel) { /* Nothing... */ }
            },
            message: {
                Text("A saved filter with the same name already exists. Replacing it will override its current contents.")
            }
        )
        .alert(
            "Duplicate filter “\(self.duplicateQueryName)” already exists. Save a copy?",
            isPresented: self.$isShowingDuplicateAlert,
            actions: {
                Button("Save") {
                    self.query.name = self.savedQueryName
                    
                    // No need to check the name again here because we do that first.
                    self.saveQuery(checkDuplicate: false, checkName: false, event: "Save Duplicate Filter")
                }
                Button("Cancel", role: .cancel) { /* Nothing... */ }
            },
            message: {
                Text("A saved filter with the same contents already exists. Saving will create a new filter that is a copy of the existing filter.")
            }
        )
    }
    
    func saveQuery(checkDuplicate: Bool, checkName: Bool, event: String) {
        // First we check if we already have a query with the same name and confirm the replacement.
        if checkName, let _ = self.savedQueries.queryNamed(self.savedQueryName) {
            self.isShowingReplaceAlert = true
            return
        }
        
        // Next, we check if there's already a query that's exactly the same as this one.
        // If the existing duplicate query has the same name as this one, then we're okay.
        if checkDuplicate,
           let existingQuery = self.savedQueries.queryMatching(self.query),
           existingQuery.name != self.savedQueryName {
            self.duplicateQueryName = existingQuery.name
            self.isShowingDuplicateAlert = true
            return
        }
        
        // We made it through our checks. Let's save the query.
        // Give this query a new unique ID so that it doesn't collide with anything else.
        self.query.assignNewIDs()
        self.query.name = self.savedQueryName
        self.savedQueries.save(self.query)
        
        Analytics.track(event, self.query.topLevelQuery.analyticsProperties)
    }
    
    func addNewColorization() {
        let usedColors = Set(self.query.colorizations.map { $0.color })
        let possibleColors = Set(ColorChoice.allCases)
        var remainingColors = possibleColors
        remainingColors.subtract(usedColors)
        if remainingColors.isEmpty {
            remainingColors = possibleColors
        }
        let color = remainingColors.randomElement() ?? .red
        let newColorizeQuery = Colorization(query: .defaultColorizeQuery, color: color)
        self.query.colorizations.insert(newColorizeQuery, at: 0)
    }
}

struct SavedQueriesView : View {
    
    @Environment(SavedQueries.self) var savedQueries
    
    @Binding var isShowingSaveAlert: Bool
    
    @State var isShowingRenameAlert = false
    @State var savedQueryName = ""
    @State var savedQueryToRename: UserQuery?
    
    @State private var isShowingReplaceAlert: Bool = false
    
    var onSelect: (UserQuery) -> ()
    
    var body: some View {
        ScrollView(.horizontal) {
            
            HStack(spacing: 4) {
                
                ForEach(self.savedQueries.savedQueries) { savedQuery in
                    
                    Button {
                        // The user selected this saved query.
                        // When adding a saved query, let's change the unique ID.
                        // That way, it doesn't collide with anything else in the UI.
                        var query = savedQuery
                        query.assignNewIDs()
                        self.onSelect(query)
                    } label: {
                        Text(verbatim: savedQuery.name)
                    }
                    .buttonStyle(.accessoryBar)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Add filter named \(savedQuery.name)")
                    .contextMenu {
                        Button("Rename") {
                            self.savedQueryToRename = savedQuery
                            self.savedQueryName = savedQuery.name
                            self.isShowingRenameAlert = true
                            Analytics.track("Rename Filter", savedQuery.topLevelQuery.analyticsProperties)
                        }
                        Button("Delete") {
                            self.savedQueries.remove(savedQuery)
                            Analytics.track("Delete Filter", savedQuery.topLevelQuery.analyticsProperties)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .alert(
            "Rename saved filter?",
            isPresented: self.$isShowingRenameAlert,
            actions: {
                TextField("Filter name", text: self.$savedQueryName)
                Button("Save") {
                    guard var queryToSave = self.savedQueryToRename else { return }
                    queryToSave.name = self.savedQueryName
                    // First we check if we already have a query with the same name and confirm the replacement.
                    if let _ = self.savedQueries.queryNamed(self.savedQueryName) {
                        self.isShowingReplaceAlert = true
                    } else {
                        queryToSave.name = self.savedQueryName
                        self.savedQueries.save(queryToSave)
                        Analytics.track("Rename Saved Filter")
                    }
                }
                .disabled(self.savedQueryName.isEmpty)
                Button("Cancel", role: .cancel) { /* Nothing... */ }
            },
            message: {
                Text("Enter a new name for your saved filter.")
            }
        )
    }
}

// MARK: - Preview

#Preview {
    
    PreviewBindingHelper(
        UserQuery(
            topLevelQuery: .and([
                
                // Default
                UserQuery().topLevelQuery,
                
                // Lots of subqueries
                .or([
                    .equals(.pid, "com.apple"),
                    .doesNotEqual(.sender, ""),
                    .contains(.thread, ""),
                    .doesNotContain(.activity, ""),
                ]),
                
                // Nested compound queries
                .and([
                    .doesNotContain(.subsystem, "com.jolly"),
                    .or([
                        .contains(.category, "Sync"),
                        .contains(.message, "Data"),
                    ])
                ]),
                
                // Funky nested compound queries with no subqueries
                .and([
                    .or([]),
                    .or([
                        .or([]),
                        .and([]),
                    ])
                ]),
            ]),
            colorizations: [
                Colorization(query: .defaultColorizeQuery, color: .yellow),
                Colorization(query: .or([.contains(.message, "Starting operation")]), color: .blue),
                Colorization(query: .or([.contains(.message, "Finished operation")]), color: .red),
                Colorization(query: .or([.logLevel()]), color: .green)
            ]
        )
    ) { binding in
        QuerySectionView(query: binding)
            .frame(width: 800)
            .environment(SavedQueries.previewQueries())
    }
}
