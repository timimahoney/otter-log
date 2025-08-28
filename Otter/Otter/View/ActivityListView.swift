//
//  ActivityListView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/7/24.
//

import Foundation
import OSLog
import SwiftUI

struct ActivityListView : View {
    
    @Binding var data: FilteredData
    @Binding var filter: String
    @Binding var selection: Set<Activity.ID>
    @Binding var progress: Progress?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    
    /// The count we use for the "# Selected" button.
    /// Use a separate property from `selection` so that we can animate it.
    @State var selectionCount: Int = 0
    
    init(
        data: Binding<FilteredData>,
        filter: Binding<String>,
        selection: Binding<Set<Activity.ID>>,
        progress: Binding<Progress?>,
        columnVisibility: Binding<NavigationSplitViewVisibility>
    ) {
        self._data = data
        self._filter = filter
        self._selection = selection
        self._progress = progress
        self._columnVisibility = columnVisibility
    }
    
    var body: some View {
        
        VStack(spacing: 0) {
            TextField("Filter Activities", text: self.$filter)
                .padding([.leading, .trailing], 8)
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 4)
            
            Divider()
            
            ActivityOutlineView(
                data: self.data,
                selection: self.$selection
            )
            .onChange(of: self.selection) { oldValue, newValue in
                withAnimation(.otter) {
                    self.selectionCount = self.selection.count
                }
                
                Analytics.track("Select Activity", [
                    .analytics_activityCount : newValue.count,
                ])
            }
            
            Divider()
            
            HStack(alignment: .center, spacing: 8) {
                Text("\(self.data.activities.count.formatted()) Activities")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if self.selectionCount > 0 {
                    Divider()
                        .frame(height: 8)
                    Button {
                        self.selection = []
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("\(self.selectionCount.formatted()) Selected")
                                .lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.accent)
                }
            }
            .padding(8)
        }
        .toolbar {
            if self.columnVisibility != .detailOnly, let progress = self.progress {
                Spacer()
                ProgressView(progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .labelsHidden()
                    .opacity(0.5)
            }
        }
    }
}

// MARK: - Outline View

struct ActivityOutlineView : NSViewRepresentable {
    
    static let tableColumnID = NSUserInterfaceItemIdentifier("ActivityColumn")
    static let cellHeight: CGFloat = 48
    
    let data: FilteredData
    @Binding var selection: Set<Activity.ID>
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(activities: self.data.activities) { newSelection in
            self.selection = Set(newSelection)
        }
        return coordinator
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = NSOutlineView()
        outlineView.backgroundColor = .clear
        outlineView.allowsMultipleSelection = true
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.headerView = nil
        outlineView.style = .fullWidth
        outlineView.indentationPerLevel = 6

        outlineView.addTableColumn(NSTableColumn(identifier: Self.tableColumnID))
        
        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let activities = self.data.activities
        context.coordinator.activities = activities
        
        if let first = activities.first, let last = activities.last {
            context.coordinator.shouldShowDates = abs(last.date.timeIntervalSince(first.date)) > 24 * 60 * 60
        }
        
        if let outlineView = nsView.documentView as? NSOutlineView {
            outlineView.reloadData()
            if !self.selection.isEmpty {
                let recursiveActivities = self.data.recursiveActivitiesByID
                let selectedActivities = self.selection.compactMap { recursiveActivities[$0] }
                let rowsToSelect = selectedActivities.map { outlineView.row(forItem: $0) }
                outlineView.selectRowIndexes(IndexSet(rowsToSelect), byExtendingSelection: false)
            }
        } else {
            Logger.ui.error("Activity list view is not an outline view: \(type(of: nsView.documentView))")
        }
    }
}

// MARK: - Coordinator

extension ActivityOutlineView {
    final class Coordinator : NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {
        
        var activities: [Activity]
        var shouldShowDates = false
        
        var onSelectionChange: ([Activity.ID]) -> ()
        
        init(activities: [Activity], onSelectionChange: @escaping ([Activity.ID]) -> ()) {
            self.activities = activities
            self.onSelectionChange = onSelectionChange
        }
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return self.activities.count
            } else if let activity = item as? Activity {
                return activity.subactivityIDs.count
            } else {
                Logger.ui.error("Got an item for the activity view, but it wasn't an activity: \(type(of: item))")
                return 0
            }
        }
        
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            return ActivityOutlineView.cellHeight
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                if index >= self.activities.count {
                    fatalError("Tried to get an activity at index \(index) past the bounds (\(self.activities.count))")
                }
                return self.activities[index]
            } else if let activity = item as? Activity {
                guard let subactivities = activity.subactivities else {
                    fatalError("Tried to get a child of an activity with no sub-activities: \(activity)")
                }
                if index >= subactivities.count {
                    fatalError("Tried to get a child of an activity at index \(index) past the subactivity bounds (\(subactivities.count)): \(activity)")
                }
                return subactivities[index]
            } else {
                fatalError("Tried to get a child of something that isn't an activity: \(type(of: item))")
            }
        }
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            let cellIdentifier = NSUserInterfaceItemIdentifier("ActivityCell")
            guard tableColumn?.identifier == ActivityOutlineView.tableColumnID else {
                Logger.ui.error("Tried to get an activity cell for the wrong table column ID: \(tableColumn)")
                return nil
            }
            guard let activity = item as? Activity else {
                Logger.ui.error("Outline view item was not an activity: \(type(of: item))")
                return nil
            }
            
            let itemRow = outlineView.row(forItem: item)
            let isSelected = outlineView.selectedRowIndexes.contains(itemRow)
            
            // TODO: Cell re-use.
            let cell = NSTableCellView()
            cell.identifier = cellIdentifier
            let activityCell = ActivityCell(
                activity: activity,
                shouldShowDate: self.shouldShowDates,
                isSelected: isSelected
            ) {
                let itemRow = outlineView.row(forItem: item)
                if itemRow != -1 {
                    outlineView.deselectRow(itemRow)
                }
            }
            let hostingView = NSHostingView(rootView: activityCell)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(hostingView)
            
            let constraints = [
                NSLayoutConstraint(item: hostingView, attribute: .width, relatedBy: .equal, toItem: cell, attribute: .width, multiplier: 1, constant: 0),
                NSLayoutConstraint(item: hostingView, attribute: .height, relatedBy: .equal, toItem: cell, attribute: .height, multiplier: 1, constant: 0),
            ]
            NSLayoutConstraint.activate(constraints)
            return cell
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let activity = item as? Activity else {
                fatalError("Tried to check isItemExpandable for non-Activity item: \(type(of: item))")
            }
            return activity.subactivityIDs.count > 0
        }
        
        func outlineViewItemDidExpand(_ notification: Notification) {
            Analytics.track("Expand Activity")
        }
        
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let level = outlineView.level(forItem: item)
            let identifier = NSUserInterfaceItemIdentifier("ActivityRowView-\(level)")
            if let rowView = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableRowView {
                return rowView
            } else {
                let rowView = NSTableRowView()
                rowView.identifier = identifier
                switch level {
                case 0:
                    break
                default:
                    rowView.wantsLayer = true
                    let color: Color
                    switch outlineView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
                    case .aqua?:
                        let opacity = min(0.06 * Double(level), 0.3)
                        color = Color.primary.opacity(opacity)
                    case .darkAqua?:
                        let opacity = min(0.15 * Double(level), 0.5)
                        color = Color.primary.opacity(opacity)
                    default:
                        color = .clear
                    }
                    
                    let cgColor = color.resolve(in: .init()).cgColor
                    rowView.layer?.backgroundColor = cgColor
                    
                }
                return rowView
            }
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else {
                Logger.ui.error("Tried to get outline view from notification, but failed: \(notification)")
                return
            }
            
            let selectedActivities = outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? Activity }
            let selectedActivityIDs = selectedActivities.map { $0.id }
            self.onSelectionChange(selectedActivityIDs)
        }
    }
}

// MARK: - Cells

struct ActivityCell : View {
    
    @State var activity: Activity
    let shouldShowDate: Bool
    let isSelected: Bool
    
    var close: () -> Void = {}
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            Spacer(minLength: 1)
            
            HStack(alignment: .center, spacing: 0) {
                
                // Activity name
                let noName = self.activity.name.isEmpty
                Text(verbatim: noName ? String(localized: "No activity name") : self.activity.name)
                    .foregroundStyle(noName ? .secondary : .primary)
                    .font(.subheadline.monospaced().weight(.medium))
                    .lineLimit(1)

                // If the activity is selected, we show a little X button to de-select it.
                if self.isSelected {
                    Spacer()
                    
                    Button {
                        self.close()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .accessibilityHint("Deselect activity")
                                .imageScale(.small)
                        }
                        .padding(6) // extra clickable space
                        .background(.white.opacity(0.000001)) // need some sort of background for the space to be clickable
                            
                    }
                    .labelsHidden()
                    .padding(-6) // the extra clickable space shouldn't affect layout.
                    .buttonStyle(.plain)
                    .padding(.trailing, -1) // alignment...
                    
                    
                }
            }
            .padding([.bottom], 4)
            
            HStack(alignment: .center, spacing: 0) {
                
                // Process
                Text(verbatim: self.activity.process)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                // Date
                let dateFormatter = self.shouldShowDate ? Self.dateFormatterWithDate : Self.dateFormatterWithoutDate
                Text(verbatim: dateFormatter.string(from: self.activity.date))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 1)
            
            Color.secondary.opacity(0.2)
                .frame(height: 1)
        }
        .padding([.leading, .trailing], 8)
        .frame(height: ActivityOutlineView.cellHeight)
    }

    static let dateFormatterWithoutDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    static let dateFormatterWithDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd HH:mm:ss")
        return formatter
    }()
}

#Preview {
    PreviewBindingHelper(FilteredData.previewData()) { data in
        PreviewBindingHelper(Set<Activity.ID>()) { selection in
            NavigationSplitView {
                ActivityListView(
                    data: data,
                    filter: .constant(""),
                    selection: selection,
                    progress: .constant(Progress()),
                    columnVisibility: .constant(.all)
                )
                .navigationSplitViewColumnWidth(ideal: 224)
            } detail: {
                Text("hey!")
            }
        }
    }
}
