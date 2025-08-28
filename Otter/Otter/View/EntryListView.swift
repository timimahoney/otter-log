//
//  EntryListView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/7/24.
//

import AppKit
import Foundation
import OSLog
import SwiftUI

struct EntryListView : NSViewRepresentable {
    
    @Binding var data: FilteredData
    @Binding var colorizations: [Colorization]
    @Binding var displayedDateRange: ClosedRange<Date>
    
    @Binding var dateToScroll: Date?
    
    var onSelectionChange: ([Entry]) -> ()
    var onSelectEntryMenuItem: ((EntryTableView.MenuItem) -> ())?
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            data: self.data,
            colorizations: self.colorizations,
            onSelectionChange: self.onSelectionChange,
            onVisibleRangeChange: { newDateRange in
                self.displayedDateRange = newDateRange
            }
        )
        return coordinator
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let tableView = EntryTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowSizeStyle = .small
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.allowsMultipleSelection = true
        tableView.delegate = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = context.coordinator
        tableView.coordinator = context.coordinator
        tableView.textFinder = context.coordinator.textFinder
        tableView.onCopy = {
            context.coordinator.onCopy()
        }
        tableView.onSelectMenuItem = { entryMenuItem in
            self.onSelectEntryMenuItem?(entryMenuItem)
        }
        context.coordinator.tableView = tableView
        
        for property in Entry.Property.allCases {
            let column = NSTableColumn(identifier: property.tableColumnIdentifier)
            column.title = property.tableColumnTitle
            column.width = property.tableColumnWidth
            if !property.tableColumnAllowResize {
                column.maxWidth = column.width
                column.minWidth = column.width
            }
            column.isHidden = property.isHiddenByDefault
            tableView.addTableColumn(column)
        }
        
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.findBarPosition = .aboveContent
        
        context.coordinator.scrollView = scrollView
        context.coordinator.startListeningForNotifications()
        
        context.coordinator.textFinder.client = context.coordinator
        context.coordinator.textFinder.findBarContainer = scrollView
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let previousEntries = context.coordinator.data.entries
        
        let newData = self.data
        let newEntries = newData.entries
        context.coordinator.data = newData
        let previousColorizations = context.coordinator.colorizations
        context.coordinator.colorizations = self.colorizations
        context.coordinator.textFinder.noteClientStringWillChange()
        context.coordinator.searchIndex.entries = newEntries
        
        if let tableView = context.coordinator.tableView {
            
            /// If we're updating the entry list with new entries from loading a new batch from the log archive,
            /// then we just prepended the new entries to the old ones, so we don't have to completely reload everything (via `reloadData`).
            /// By not calling `reloadData`, we can maintain our existing selection and scroll position.
            /// If we're not sure that we just prepended new data, then we have to go through the more drastic `reloadData` path.
            var shouldReloadData = true
            let hasNewColorizations = (previousColorizations != self.colorizations)
            let entryCountDifference = newEntries.count - previousEntries.count
            if !hasNewColorizations && !previousEntries.isEmpty && !newEntries.isEmpty && entryCountDifference >= 0 {
                let maybeFirstPreviousEntry = newEntries[entryCountDifference]
                let maybeLastPreviousEntry = newEntries[previousEntries.count - 1 + entryCountDifference]
                if maybeFirstPreviousEntry == previousEntries.first && maybeLastPreviousEntry == previousEntries.last {
                    
                    // Do some calculations to try to keep the same vertical scroll offset.
                    let visibleRect = tableView.visibleRect
                    let visibleRange = tableView.rows(in: visibleRect)
                    let previousFirstVisibleRowRect = tableView.rect(ofRow: visibleRange.location)
                    var firstRowScrollOffset = 0.0
                    if previousFirstVisibleRowRect.origin.y != 0 {
                        firstRowScrollOffset = visibleRect.origin.y - previousFirstVisibleRowRect.origin.y
                        
                        // I don't know why, but sometimes we end up with a very high number that's obviously wrong.
                        // There's probably an explanation for this, but I can't be bothered to figure it out right now.
                        if abs(firstRowScrollOffset) > tableView.rowHeight {
                            firstRowScrollOffset = 0
                        }
                    }
                    
                    tableView.beginUpdates()
                    let indexes = IndexSet(integersIn: 0..<entryCountDifference)
                    tableView.insertRows(at: indexes)
                    tableView.endUpdates()
                    shouldReloadData = false
                    
                    // Finally, try to preserve the scroll location from before.
                    let newFirstVisibleRow = visibleRange.location + entryCountDifference
                    let newFirstVisibleRowRect = tableView.rect(ofRow: newFirstVisibleRow)
                    var scrollTarget = newFirstVisibleRowRect.origin
                    scrollTarget.y += firstRowScrollOffset
                    tableView.scroll(scrollTarget)
                }
            }
            
            if shouldReloadData {
                tableView.reloadData()
            }
        }
        
        if let dateToScroll = self.dateToScroll {
            context.coordinator.scroll(to: dateToScroll)
            self.dateToScroll = nil
        } else {
            context.coordinator.updateDisplayedDateRange()
        }
    }
    
    final class Coordinator : NSObject, NSTableViewDelegate, NSTableViewDataSource, NSFetchedResultsControllerDelegate, NSTextFinderClient {
        
        var data: FilteredData
        var colorizations: [Colorization]
        var onSelectionChange: ([Entry]) -> ()
        
        var onVisibleRangeChange: (ClosedRange<Date>) -> ()
        
        weak var scrollView: NSScrollView?
        weak var tableView: NSTableView?
        
        let textFinder = NSTextFinder()
        var searchIndex = SearchIndex()
        
        init(
            data: FilteredData,
            colorizations: [Colorization],
            onSelectionChange: @escaping ([Entry]) -> (),
            onVisibleRangeChange: @escaping (ClosedRange<Date>) -> ()
        ) {
            self.data = data
            self.colorizations = colorizations
            self.onSelectionChange = onSelectionChange
            self.onVisibleRangeChange = onVisibleRangeChange
            super.init()
        }
        
        func startListeningForNotifications() {
            // Listen for scrolling so that we can update the visible date range.
            guard let scrollView = self.scrollView, let tableView = self.tableView else {
                return
            }
            
            let notificationCenter = NotificationCenter.default
            notificationCenter.removeObserver(self)
            notificationCenter.addObserver(
                self,
                selector: #selector(Coordinator.boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            
            notificationCenter.addObserver(self, selector: #selector(Coordinator.selectionChanged(_:)), name: NSTableView.selectionDidChangeNotification, object: tableView)
        }
        
        // MARK: - Timeline
        
        @MainActor
        @objc func boundsDidChange(_ notification: Notification) {
            self.updateDisplayedDateRange()
            
            // TODO: Should we animate this? If so, we might want to debounce the changes.
        }
        
        @MainActor
        func updateDisplayedDateRange() {
            guard let tableView = self.tableView else { return }
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            let firstRow = visibleRange.location
            let entries = self.data.entries
            let lastRow = min(firstRow + visibleRange.length, entries.count - 1)
            if firstRow < entries.count {
                let first = entries[firstRow].date
                var last = entries[lastRow].date
                if first == last {
                    last += 1
                }
                let newDateRange = first...last
                self.onVisibleRangeChange(newDateRange)
            }
        }
        
        @MainActor
        func scroll(to date: Date) {
            guard let tableView = self.tableView else { return }
            
            let index = self.data.entries.ot_binaryFirstIndex { $0.date > date }
            if let index {
                tableView.scrollRowToVisible(index)
            }
        }
        
        // MARK: - Copy
        
        func onCopy() {
            guard let selectedRows = self.tableView?.selectedRowIndexes,
            !selectedRows.isEmpty else { return }
            
            let selectedEntries = self.data.entries[selectedRows]
            let pasteboardText = selectedEntries.map { $0.plaintextRepresentation }.joined(separator: "\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(pasteboardText, forType: .string)
            
            Analytics.track("Copy from Entry List", [
                .analytics_entryCount : selectedRows.count,
            ])
        }
    }
}

// MARK: - Find / NSTextFinderClient

extension EntryListView.Coordinator {
    
    var isEditable: Bool { false }
    
    var firstSelectedRange: NSRange {
        let firstSelectedRow = self.tableView?.selectedRowIndexes.first
        return self.searchIndex.firstSelectedRange(firstSelectedRow)
    }
    
    func string(at characterIndex: Int, effectiveRange outRange: NSRangePointer, endsWithSearchBoundary outFlag: UnsafeMutablePointer<ObjCBool>) -> String {
        return self.searchIndex.string(at: characterIndex, effectiveRange: outRange, endsWithSearchBoundary: outFlag)
    }
    
    func stringLength() -> Int {
        return self.searchIndex.stringLength()
    }
    
    func scrollRangeToVisible(_ range: NSRange) {
        guard let tableView = self.tableView, let scrollView = tableView.enclosingScrollView else { return }
        if let row = self.searchIndex.row(range) {
            // Try to put this row in the middle by scrolling both ahead and behind.
            let visibleRowCount = Int(scrollView.frame.size.height / tableView.rowHeight)
            let contextCount = max((visibleRowCount / 2) - 1, 0)
            let lookAheadRow = min(row + contextCount, tableView.numberOfRows - 1)
            let lookBehindRow = max(row - contextCount, 0)
            tableView.scrollRowToVisible(row)
            tableView.scrollRowToVisible(lookAheadRow)
            tableView.scrollRowToVisible(lookBehindRow)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            Logger.find.error("Couldn't find row to scroll for found range \(range)")
        }
    }
}

// MARK: - NSTableViewDelegate/DataSource

extension EntryListView.Coordinator {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.data.entries.count
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let entry = self.data.entries[row]
        
        let context = FilterContext()
        let matchingColorChoice = self.colorizations.first { $0.query.optimized()?.evaluate(entry, context) ?? false }?.color
        
        let identifierName = "EntryRowView-\(matchingColorChoice?.rawValue ?? "None")"
        let identifier = NSUserInterfaceItemIdentifier(identifierName)
        if let rowView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableRowView {
            return rowView
        } else {
            let rowView = OtterEntryRowView()
            rowView.identifier = identifier
            rowView.color = matchingColorChoice?.color
            return rowView
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else {
            Logger.ui.error("No table column for table cell view")
            return nil
        }
        guard let property = Entry.Property(rawValue: column.identifier.rawValue) else {
            Logger.ui.error("No entry property enum for column \(column.identifier.rawValue)")
            return nil
        }
        
        let entry = self.data.entries[row]
        let cellValue = entry.cellValue(for: property)
        
        let result: NSTableCellView?
        
        switch cellValue {
        case let string as String:
            let cellIdentifier = column.identifier
            let cellView: NSTableCellView
            let sanitizedString = string.replacing("\n", with: " ")
            
            if let existingCellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
                cellView = existingCellView
                guard let textField = cellView.subviews.first as? NSTextField else {
                    Logger.ui.error("Found a cell view without a text field")
                    return nil
                }
                textField.stringValue = sanitizedString
            } else {
                cellView = NSTableCellView()
                cellView.identifier = cellIdentifier
                cellView.clipsToBounds = true
                cellView.autoresizingMask = [ .height, .maxYMargin, .minYMargin ]
                
                let textField = NSTextField(labelWithString: sanitizedString)
                textField.isSelectable = false
                textField.isEditable = false
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                textField.lineBreakMode = .byTruncatingTail
                cellView.addSubview(textField)
                
                // Center the text field vertically in the cell. What a trip!
                NSLayoutConstraint.activate([NSLayoutConstraint(item: textField, attribute: .centerY, relatedBy: .equal, toItem: cellView, attribute: .centerY, multiplier: 1, constant: 0)])
            }
            
            cellView.toolTip = string
            result = cellView
            
        case let color as Color:
            let cellIdentifier = column.identifier
            let cellView: NSTableCellView
            let fillColor: CGColor?, strokeColor: CGColor?
            if color == Color.clear {
                fillColor = nil
                strokeColor = nil
            } else {
                fillColor = NSColor(color).blended(withFraction: 0.2, of: NSColor.white)?.cgColor
                strokeColor = NSColor(color).cgColor
            }
            if let existingCellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
                cellView = existingCellView
                guard let shapeLayer = cellView.subviews.first?.layer as? CAShapeLayer else {
                    fatalError("Found a cell view without a circle shape layer")
                }
                shapeLayer.fillColor = fillColor
                shapeLayer.strokeColor = strokeColor
            } else {
                let size = 8.0
                cellView = NSTableCellView()
                cellView.clipsToBounds = true
                
                let circleView = NSView()
                circleView.translatesAutoresizingMaskIntoConstraints = false
                circleView.wantsLayer = true
                let shapeLayer = CAShapeLayer()
                shapeLayer.lineWidth = 1
                shapeLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
                shapeLayer.fillColor = fillColor
                shapeLayer.strokeColor = strokeColor
                circleView.layer = shapeLayer
                cellView.addSubview(circleView)
                
                // Center the circle in the cell.
                NSLayoutConstraint.activate([
                    NSLayoutConstraint(item: circleView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .height, multiplier: 1, constant: size),
                    NSLayoutConstraint(item: circleView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .width, multiplier: 1, constant: size),
                    NSLayoutConstraint(item: circleView, attribute: .centerX, relatedBy: .equal, toItem: cellView, attribute: .centerX, multiplier: 1, constant: 0),
                    NSLayoutConstraint(item: circleView, attribute: .centerY, relatedBy: .equal, toItem: cellView, attribute: .centerY, multiplier: 1, constant: 0),
                ])
            }
            
            cellView.toolTip = entry.toolTip(for: property)
            result = cellView
        default:
            result = nil
        }
        
        return result
    }
    
    func tableView(_ tableView: NSTableView, userCanChangeVisibilityOf column: NSTableColumn) -> Bool {
        return true
    }
    
    @objc func selectionChanged(_ notification: Notification) {
        let selectedRows = self.tableView?.selectedRowIndexes ?? IndexSet()
        let entries = self.data.entries[selectedRows]
        self.onSelectionChange(entries)
    }
}

// MARK: - EntryTableView

/// Just a little subclass that can respond to `copy(:)`.
class EntryTableView : NSTableView {
    
    weak var coordinator: EntryListView.Coordinator?
    
    // MARK: Copy
    
    var onCopy: (() -> (Void))?
    
    @IBAction func copy(_ sender: Any) {
        self.onCopy?()
    }
    
    // MARK: TextFinder
    
    var textFinder: NSTextFinder?
    
    override func performTextFinderAction(_ sender: Any?) {
        guard let action = (sender as? TextFinderAction)?.action else {
            Logger.find.error("Couldn't get text finder action from sender: \(String(describing: sender))")
            return
        }
        
        switch action {
        case .showFindInterface:
            Logger.find.debug("Showing text finder interface")
            self.textFinder?.performAction(action)
        case .nextMatch:
            Logger.find.debug("Next match")
            self.textFinder?.performAction(action)
        case .previousMatch:
            Logger.find.debug("Previous match")
            self.textFinder?.performAction(action)
        default:
            Logger.find.error("Unknown text finder action: \(action.rawValue)")
        }
    }
    
    // MARK: Menu
    
    struct MenuItem {
        var action: Action
        var entry: Entry
        var property: Entry.Property
        
        enum Action {
            case show
            case hide
            
            var comparison: PropertyQuery.Comparison {
                switch self {
                case .show: .equals
                case .hide: .doesNotEqual
                }
            }
        }
    }
    
    var onSelectMenuItem: ((MenuItem) -> ())?
    
    override func menu(for event: NSEvent) -> NSMenu? {
        // Create a menu for this entry.
        // It'll allow the user to add new things to their query filter.
        guard let coordinator = self.coordinator else {
            Logger.ui.error("No coordinator to generate entry menu")
            return nil
        }
        let locationInTableView = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: locationInTableView)
        let column = self.column(at: locationInTableView)
        guard row != NSNotFound, column != NSNotFound else {
            Logger.ui.error("Couldn't find row from event location for menu")
            return nil
        }
        guard row < coordinator.data.entries.count else {
            Logger.ui.error("Trying to create a menu for a row outside the bounds of the entries")
            return nil
        }
        
        // Hey look, we're all good!
        // Let's create a menu that looks like this:
        //
        // Hide Clicked Property
        // Show Clicked Property
        // ---------------------
        // Hide Other Properties
        // ------------------------
        // Show Other Properties
        let entry = coordinator.data.entries[row]
        let menu = NSMenu()
        
        var properties: [Entry.Property] = [
            .activity,
            .process,
            .pid,
            .thread,
            .subsystem,
            .category,
        ]
        
        // See if we should bump the clicked property to the top of the menu.
        let clickedColumn = self.tableColumns[column]
        let clickedProperty = Entry.Property.allCases.first { $0.tableColumnIdentifier == clickedColumn.identifier }
        if let clickedProperty, properties.contains(clickedProperty) {
            properties.removeAll { $0 == clickedProperty }
            var addSeparator = false
            if let hideItem = self.menuItem(for: clickedProperty, in: entry, action: .hide) {
                addSeparator = true
                menu.addItem(hideItem)
            }
            if let showItem = self.menuItem(for: clickedProperty, in: entry, action: .show) {
                addSeparator = true
                menu.addItem(showItem)
            }
            if addSeparator {
                menu.addItem(NSMenuItem.separator())
            }
        }
        
        // Hide
        for property in properties {
            if let hideItem = self.menuItem(for: property, in: entry, action: .hide) {
                menu.addItem(hideItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Show
        for property in properties {
            if let showItem = self.menuItem(for: property, in: entry, action: .show) {
                menu.addItem(showItem)
            }
        }
        
        return menu
    }
    
    func menuItem(for property: Entry.Property, in entry: Entry, action: MenuItem.Action) -> NSMenuItem? {
        let value = entry.stringValue(for: property)
        if value.isEmpty {
            return nil
        } else if property == .type && entry.type == .activity {
            return nil
        } else {
            let string: String
            switch action {
            case .show:
                string = String(localized: "Show \(property.localizedName) '\(value)'")
            case .hide:
                string = String(localized: "Hide \(property.localizedName) '\(value)'")
            }
            let menuItem = NSMenuItem(
                title: string,
                action: #selector(performEntryMenuItemAction(_:)),
                keyEquivalent: ""
            )
            let entryMenuItem = MenuItem(action: action, entry: entry, property: property)
            menuItem.representedObject = entryMenuItem
            return menuItem
        }
    }
    
    @IBAction func performEntryMenuItemAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            Logger.ui.error("Trying to respond to entry context menu click with no menu item")
            return
        }
        guard let entryMenuItem = menuItem.representedObject as? MenuItem else {
            Logger.ui.error("Trying to respond to entry context menu click with no entry")
            return
        }
        
        self.onSelectMenuItem?(entryMenuItem)
    }
    
}

// MARK: - Search Index

/// A little structure that helps us index our content for `NSTextFinder`.
struct SearchIndex : Sendable {
    
    /// The entries to index.
    var entries: [Entry] = [] {
        didSet {
            self.indexByRow = []
            self.nextRowToIndex = 0
        }
    }
    
    /// An index that maps the entry row/index to an `IndexElement`.
    /// It holds all the currently-indexed elements in the table.
    /// If the entries are fully indexed, then this should have one element per row in the table.
    /// You can regenerate the index with `generateIndexIfNecessary()`.
    var indexByRow: [IndexElement] = []
    
    struct IndexElement : Sendable {
        
        /// The range of the message in the entire searchable string of the whole list.
        let range: Range<Int>
        
        /// The row of the entry in ths list.
        let row: Int
        
        /// The entry message.
        let message: String
    }
    
    /// The next row we need to index.
    /// This is kept up to date as we incrementally generate the index.
    /// The next time we're asked to generate the index, we start from here.
    /// If this is `0`, then we need to index everything.
    var nextRowToIndex: Int = 0
    
    /// The lock we use around index regeneration.
    let lock = OSAllocatedUnfairLock()
    
    mutating func stringLength() -> Int {
        self.generateIndexIfNecessary()
        return self.indexByRow.last?.range.upperBound ?? 0
    }
    
    mutating func firstSelectedRange(_ selectedRow: Int?) -> NSRange {
        if let selectedRow {
            self.generateIndexIfNecessary()
            if self.indexByRow.count <= selectedRow {
                Logger.find.error("Tried to get first selected range for row without an index element \(selectedRow)")
                return NSRange(location: 0, length: 0)
            } else {
                let selectedIndexElement = self.indexByRow[selectedRow]
                let entryRange = selectedIndexElement.range
                Logger.find.debug("First selected range: \(entryRange)")
                return NSRange(location: entryRange.lowerBound, length: entryRange.count)
            }
        } else {
            Logger.find.debug("No first selected range")
            return NSRange(location: 0, length: 0)
        }
    }
    
    mutating func string(at characterIndex: Int, effectiveRange outRange: NSRangePointer, endsWithSearchBoundary outFlag: UnsafeMutablePointer<ObjCBool>) -> String {
        self.generateIndexIfNecessary()
        
        let row = Self.binarySearch(self.indexByRow, target: characterIndex)
        let message: String
        let range: Range<Int>
        if let row {
            let element = self.indexByRow[row]
            message = element.message
            range = element.range
        } else {
            Logger.find.fault("Couldn't find row in index for character \(characterIndex)")
            message = ""
            range = 0..<0
        }
        
        outRange.pointee.location = range.lowerBound
        outRange.pointee.length = range.count
        outFlag.pointee = true
        return message
    }
    
    // Thanks, ChatGPT!
    static func binarySearch(_ elements: [IndexElement], target: Int) -> Int? {
        var low = 0
        var high = elements.count - 1
        
        while low <= high {
            let mid = low + (high - low) / 2
            let currentRange = elements[mid].range
            
            if target >= currentRange.lowerBound && target < currentRange.upperBound {
                return mid // Found the range
            } else if target < currentRange.lowerBound {
                high = mid - 1 // Search in the left half
            } else {
                low = mid + 1 // Search in the right half
            }
        }
        
        return nil // Not found
    }
    
    mutating func generateIndexIfNecessary() {
        self.lock.lock()
        if self.nextRowToIndex >= self.entries.count {
            self.lock.unlock()
            return
        }
        self.generateIndex()
        self.lock.unlock()
    }
    
    mutating func generateIndex() {
        let start = Date.now
        let entries = self.entries
        
        // Generate indexes concurrently in batches.
        // Gather up the index for each concurrent batch.
        // At the end, we'll append them together in the right order.
        let batchCount = 64
        let batchSize = Swift.max(entries.count / batchCount, 100)
        let batches = stride(from: 0, to: entries.count, by: batchSize).map { batchStart in
            let batchEnd = Swift.min(batchStart + batchSize, entries.count)
            return entries[batchStart..<batchEnd]
        }
        let indexByRowBatchLock = OSAllocatedUnfairLock<[Int : [IndexElement]]>(initialState: [:])
        DispatchQueue.concurrentPerform(iterations: batches.count) { batchIndex in
            let batch = batches[batchIndex]
            var row = batchIndex * batchSize
            var previousRange = 0..<0
            let newIndexByRow = batch.map { entry in
                let messageSize = (entry.message as NSString).length // holy shit why is String.count so slow?
                let start = previousRange.upperBound
                let end = start + messageSize
                let element = IndexElement(range: start..<end, row: row, message: entry.message)
                previousRange = element.range
                row += 1
                return element
            }
            
            indexByRowBatchLock.withLock { $0[batchIndex] = newIndexByRow }
        }
        
        // Each batch index starts at 0.
        // We need to put them all next to each other and offset them accordingly.
        // In order to do this faster, we also do it concurrently.
        // However, that means we need to pre-calculate the offsets of each batch beforehand.
        let indexBatchesInOrder = indexByRowBatchLock.withLock { $0 }.sorted { $0.key < $1.key }.map { $0.value }
        let offsets: [Int] = indexBatchesInOrder.reduce(into: []) { result, indexByRowBatch in
            let currentBatchSize = indexByRowBatch.last?.range.upperBound ?? 0
            let previousOffset = result.last ?? 0
            if previousOffset == 0 {
                // This is the first element, and we want to append zero for its own offset.
                result.append(0)
            }
            // Now append an offset for the next batch start.
            // That offset is the previous batch offset plus this batch's size.
            result.append(previousOffset + currentBatchSize)
        }
        DispatchQueue.concurrentPerform(iterations: batches.count) { batchIndex in
            let indexBatch = indexBatchesInOrder[batchIndex]
            let rangeOffset = offsets[batchIndex]
            
            // Offset this batch by the appropriate amount.
            let offsetIndexByRow = indexBatch.map {
                let newLowerBound = $0.range.lowerBound + rangeOffset
                let newUpperBound = $0.range.upperBound + rangeOffset
                return IndexElement(range: newLowerBound..<newUpperBound, row: $0.row, message: $0.message)
            }
            
            let indexByRow = offsetIndexByRow
            indexByRowBatchLock.withLock { $0[batchIndex] = indexByRow }
        }
        let newIndexByRow = indexByRowBatchLock.withLock { $0 }.sorted { $0.key < $1.key }.flatMap { $0.value }
        
        self.indexByRow = newIndexByRow
        self.nextRowToIndex = entries.count
        Logger.find.debug("Finished full index in \(start.secondsSinceNowString)")
    }
    
    func row(_ characterRange: NSRange) -> Int? {
        let row = Self.binarySearch(self.indexByRow, target: characterRange.location)
        if let row {
            return row
        } else {
            Logger.find.error("Couldn't find row for range: \(characterRange)")
            return nil
        }
    }
}

// MARK: - Row View

class OtterEntryRowView : NSTableRowView {
    var color: Color?
    
    override func drawBackground(in dirtyRect: NSRect) {
        // Ideally we could just set the background in the layer, but that doesn't work for the alternating row color.
        // Let's draw according to super, then let's overlay with the color.
        super.drawBackground(in: dirtyRect)
        if let color = self.color {
            NSColor(color.opacity(0.3)).setFill()
            dirtyRect.fill()
        }
    }
}

// MARK: - Extensions

extension EntryListView : CustomStringConvertible {
    
    var description: String {
        "EntryListView(\(self.data.entries.count.formatted()) entries)"
    }
}

extension Entry {
    
    public func cellValue(for property: Entry.Property) -> Any {
        switch property {
        case .type:
            switch self.type {
            case .log:
                switch self.level {
                case .undefined:
                    return Color.clear
                case .debug:
                    return Color(NSColor.darkGray)
                case .info:
                    return Color(NSColor(white: 0.9, alpha: 1))
                case .notice:
                    return Color.clear
                case .error:
                    return Color.yellow
                case .fault:
                    return Color.red
                @unknown default:
                    return Color.clear
                }
            case .activity:
                return Color.blue
#if OTTER_SIGNPOSTS
            case .signpost:
                return Color.brown
#endif
            }
        case .activity:
            // For activities, "0" should just be blank.
            if self.activityIdentifier == 0 {
                return ""
            } else {
                return self.stringValue(for: property)
            }
        default:
            return self.stringValue(for: property)
        }
    }
    
    public func stringValue(for property: Entry.Property) -> String {
        switch property {
        case .type:
            return self.typeString
        case .date:
            return Date.otterDateString(self.date)
        case .process:
            return self.process
        case .pid:
            return "\(self.processIdentifier)"
        case .subsystem:
            return self.subsystem ?? ""
        case .category:
            return self.category ?? ""
        case .message:
            return self.message
        case .activity:
            return "\(self.activityIdentifier)"
        case .thread:
            return String(format: "0x%02x", self.threadIdentifier)
        }
    }
    
    public func toolTip(for property: Entry.Property) -> String {
        switch property {
        case .type:
            switch self.type {
            case .log:
                return self.level.description
            case .activity:
                return String(localized: "Activity")
#if OTTER_SIGNPOSTS
            case .signpost:
                return String(localized: "Signpost")
#endif
            }
        case .date, .process, .pid, .subsystem, .category, .message, .activity, .thread:
            if let string = self.cellValue(for: property) as? String {
                return string
            } else {
                return ""
            }
        }
    }
}

extension Entry.Property {
    
    var localizedName: String { String(localized: String.LocalizationValue(self.rawValue)) }
    
    var tableColumnTitle: String {
        switch self {
        case .type:
            return ""
        default:
            return self.localizedName
        }
    }
    
    var tableColumnIdentifier: NSUserInterfaceItemIdentifier { .init(self.rawValue) }
    
    var tableColumnWidth: CGFloat {
        switch self {
        case .type:       10
        case .date:       212
        case .process:    84
        case .pid:        40
        case .subsystem:  144
        case .category:   96
        case .message:    2048
        case .activity:   56
        case .thread:     56
        }
    }
    
    var tableColumnAllowResize: Bool {
        switch self {
        case .type:       false
        default:          true
        }
    }
    
    var isHiddenByDefault: Bool {
        switch self {
        case .type, .date, .process, .pid, .subsystem, .category, .message:
            return false
        case .activity, .thread:
            return true
        }
    }
}

#Preview {
    PreviewBindingHelper(FilteredData.previewData()) { data in
        PreviewBindingHelper(Date.distantPast...Date.distantFuture) { displayedDateRange in
            EntryListView(
                data: data,
                colorizations: .constant([]),
                displayedDateRange: displayedDateRange,
                dateToScroll: .constant(nil),
                onSelectionChange: { entries in
                    // Something?
                }
            )
        }
    }
}
