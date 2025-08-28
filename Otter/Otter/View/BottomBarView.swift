//
//  BottomBarView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/22/24.
//

import Foundation
import SwiftUI

struct BottomBarView : View {
    
    @Binding var userSelectedRange: ClosedRange<Date>
    @Binding var data: FilteredData
    @Binding var stats: InspectorStats
    @Binding var queryProgress: Progress?
    @Binding var loadingProgress: Progress?
    
    // Date range
    @State var userSelectedStart: Date = .distantPast
    @State var userSelectedEnd: Date = .distantFuture
    
    static let popupSelections: [DateRange] = [
        .fiveMinutes,
        .fifteenMinutes,
        .thirtyMinutes,
        .hour,
        .day,
        .all,
        .custom,
    ]
    
    @State var currentPopupSelection: DateRange = .fiveMinutes
    
    init(
        userSelectedRange: Binding<ClosedRange<Date>>,
        data: Binding<FilteredData>,
        stats: Binding<InspectorStats>,
        queryProgress: Binding<Progress?>,
        loadingProgress: Binding<Progress?>
    ) {
        self._userSelectedRange = userSelectedRange
        self._data = data
        self._stats = stats
        self._queryProgress = queryProgress
        self._loadingProgress = loadingProgress
        
        self.userSelectedStart = self.userSelectedRange.lowerBound
        self.userSelectedEnd = self.userSelectedRange.upperBound
    }
    
    var body: some View {
        
        HStack(alignment: .center) {
            
            // Never show distant past or distant future.
            let showPickers = (self.userSelectedRange != Date.distantPast...Date.distantFuture)
            
            if showPickers {
                Menu(self.currentPopupSelection.nameKey) {
                    
                    ForEach(Self.popupSelections) { selection in
                        // Add a divider between the actual time periods and "Custom"
                        if selection == .custom {
                            Divider()
                        }
                        
                        Button(selection.nameKey) {
                            let newRange: ClosedRange<Date>
                            switch selection {
                            case .custom:
                                newRange = self.userSelectedRange
                            case .all:
                                newRange = self.data.database.range
                            default:
                                // This is one of the known/default 5/15/30/etc minutes selections.
                                let timeSpan = selection.timeIntervalBeforeEnd ?? 0
                                let end = self.data.database.range.upperBound
                                let start = (end - timeSpan)
                                newRange = start...end
                            }
                            self.userSelectedStart = newRange.lowerBound
                            self.userSelectedEnd = newRange.upperBound
                            self.userSelectedRange = newRange
                            self.currentPopupSelection = selection
                            
                            Analytics.track("Select Range From Popup", [
                                .analytics_dateRange : newRange.upperBound.timeIntervalSince(newRange.lowerBound),
                                .analytics_selection : "\(selection.nameKey)",
                            ])
                        }
                    }
                }
                .controlSize(.small)
                .frame(maxWidth: 160)
                .accessibilityHint("Date range picker")
                
                DatePicker(
                    "Start",
                    selection: self.$userSelectedStart,
                    in: self.data.database.range.lowerBound...self.userSelectedEnd
                )
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: self.userSelectedStart) {
                    // Let's update the visible range property binding.
                    self.userSelectedRange = self.userSelectedStart...self.userSelectedEnd
                    self.updatePopupSelectionFromCurrentRange()
                }
                
                Image(systemName: "arrow.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                
                DatePicker(
                    "End",
                    selection: self.$userSelectedEnd,
                    in: self.userSelectedStart...self.data.database.range.upperBound
                )
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: self.userSelectedEnd) {
                    // Let's update the visible range property binding.
                    self.userSelectedRange = self.userSelectedStart...self.userSelectedEnd
                    self.updatePopupSelectionFromCurrentRange()
                }
            }
            
            Spacer()
            
            //
            // Stats (filtered)
            //
            StatsView(
                data: self.$data,
                queryProgress: self.$queryProgress,
                loadingProgress: self.$loadingProgress
            )
        }
        .frame(maxWidth: .infinity)
        .padding([.leading, .trailing], 8)
        .padding([.top, .bottom], 4)
        .onChange(of: self.userSelectedRange) { oldValue, newValue in
            self.userSelectedStart = newValue.lowerBound
            self.userSelectedEnd = newValue.upperBound
        }
    }
    
    func updatePopupSelectionFromCurrentRange() {
        let possibleRange = self.data.database.range
        let visibleRange = self.userSelectedRange
        if visibleRange.upperBound == possibleRange.upperBound {
            let timeRange = visibleRange.upperBound.timeIntervalSince(visibleRange.lowerBound)
            let knownRange = Self.popupSelections.first { $0.timeIntervalBeforeEnd == timeRange }
            if let knownRange {
                self.currentPopupSelection = knownRange
            } else if visibleRange == possibleRange {
                self.currentPopupSelection = .all
            } else {
                self.currentPopupSelection = .custom
            }
        }
    }
}

#Preview {
    PreviewBindingHelper(Date.now.addingTimeInterval(-26 * 60 * 60)...Date.now) { range in
        PreviewBindingHelper(FilteredData.previewData()) { data in
            PreviewBindingHelper(Progress()) { progress in
                BottomBarView(
                    userSelectedRange: range,
                    data: data,
                    stats: .constant(.init()),
                    queryProgress: .constant(nil),
                    loadingProgress: .constant(nil)
                )
                .frame(width: 900)
            }
        }
    }
}
