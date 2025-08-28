//
//  TimelineView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/24/24.
//

import Foundation
import SwiftUI
import Charts

struct TimelineView : View {
    
    static let height = 48.0
    nonisolated static let minimumNonZeroChunkCount = 4
    
    @Binding var data: FilteredData
    @Binding var displayedDateRange: ClosedRange<Date>
    
    @State var chunks: [ChartChunk] = []
    @State var showChunkLoadingOverlay = false
    
    var onSelect: ((Date) -> ())?
    
    struct ChartChunk : Identifiable {
        var id: Date { self.date }
        var date: Date { self.range.lowerBound }
        var range: ClosedRange<Date>
        var count: Int = 0
    }
    
    var body: some View {
        VStack {
            if self.chunks.isEmpty {
                // Dont' show anything.
                Color.clear
                    .frame(height: 0)
            } else {
                Chart(self.chunks) { chunk in
                    AreaMark(
                        x: .value("Date Start", chunk.range.lowerBound),
                        y: .value("Count", chunk.count)
                    )
                    .interpolationMethod(.stepCenter)
                }
                .frame(height: Self.height)
                .chartYScale(type: .squareRoot)
                .chartYAxis(.hidden)
                .chartOverlay { proxy in
                    
                    // Overlay the little cursor over the timeline view.
                    if let startPosition = proxy.position(forX: self.displayedDateRange.lowerBound),
                       let endPosition = proxy.position(forX: self.displayedDateRange.upperBound) {
                        let minWidth = 8.0
                        let x = max(0, min(startPosition, proxy.plotSize.width - minWidth))
                        let lastAllowedEnd = proxy.plotSize.width
                        let xEnd = min(endPosition, lastAllowedEnd)
                        let width = max(xEnd - x, minWidth)
                        
                        let cornerRadius = 3.0
                        let leadingCornerRadius = (x == 0) ? 0 : cornerRadius
                        let trailingCornerRadius = (xEnd == lastAllowedEnd) ? 0 : cornerRadius
                        let cornerRadii = RectangleCornerRadii(
                            topLeading: leadingCornerRadius,
                            bottomLeading: leadingCornerRadius,
                            bottomTrailing: trailingCornerRadius,
                            topTrailing: trailingCornerRadius
                        )
                        
                        let isCursorFullWidth = (x == 0 && xEnd == lastAllowedEnd)
                        let shouldShowCursor = !isCursorFullWidth && self.chunks.count > 1
                        if shouldShowCursor {
                            
                            // HStack
                            // |                                                |
                            // | ---- x offset ---- [CURSOR] ---- [SPACER] ---- |
                            // |                                                |
                            HStack(alignment: .top, spacing: 0) {
                                
                                //
                                // Cursor
                                //
                                UnevenRoundedRectangle(cornerRadii: cornerRadii)
                                    .fill(.white)
                                    .frame(width: width)
                                    .frame(maxHeight: .infinity)
                                    .blendMode(.colorDodge)
                                    .opacity(0.4)
                                    .overlay(
                                        UnevenRoundedRectangle(cornerRadii: cornerRadii)
                                            .strokeBorder(.tertiary)
                                    )
                                    .frame(width: width, height: proxy.plotSize.height)
                                    .offset(x: x)
                                    .allowsHitTesting(false)
                                
                                //
                                // Spacing to the right of the cursor.
                                //
                                Spacer(minLength: 0)
                            }
                            .frame(height: proxy.plotSize.height)
                            .padding([.bottom], Self.height - proxy.plotSize.height)
                        }
                    }
                }
                .overlay {
                    if self.showChunkLoadingOverlay {
                        Color(NSColor.windowBackgroundColor).opacity(0.8)
                    }
                }
                .chartGesture { proxy in
                    DragGesture(minimumDistance: -1)
                        .onChanged { newValue in
                            if let date: Date = proxy.value(atX: newValue.location.x) {
                                self.onSelect?(date)
                            }
                        }
                }
            }
        }
        .onChange(of: self.data.lastRegenerateEntriesDate) { oldValue, newValue in
            self.regenerateTimelineChunks()
        }
    }
    
    @State var regenerateTask: Task<Void, Error>?
    
    func regenerateTimelineChunks() {
        let start = Date.now
        Logger.ui.debug("Regenerating timeline chunks")
        
        self.regenerateTask?.cancel()
        
        // Only show the loading overlay if it takes a while.
        // We'll cancel t his when we set the new chunks.
        let loadingChunksTask = Task.detached {
            try await Task.sleep(for: .seconds(0.1))
            try await MainActor.run {
                try Task.checkCancellation()
                withAnimation(.snappy(duration: 0.1)) {
                    self.showChunkLoadingOverlay = true
                }
            }
        }
        
        let entries = self.data.entries
        self.regenerateTask = Task.detached(priority: .userInitiated) {
            let generatedChunks = Self.chunks(from: entries)
            
            // If there aren't enough interesting chunks, we don't want to show any.
            let nonZeroChunkCount = generatedChunks.filter { $0.count > 0 }.count
            let chunks = (nonZeroChunkCount >= Self.minimumNonZeroChunkCount) ? generatedChunks : []
            
            try Task.checkCancellation()
            
            try await MainActor.run {
                try Task.checkCancellation()
                self.chunks = chunks
                loadingChunksTask.cancel()
                if self.showChunkLoadingOverlay {
                    withAnimation(.snappy(duration: 0.1)) {
                        self.showChunkLoadingOverlay = false
                    }
                }
                self.regenerateTask = nil
                Logger.ui.debug("Finished regenerating timeline chunks in \(start.secondsSinceNowString)")
            }
        }
    }
    
    nonisolated static func chunks(from entries: [Entry]) -> [ChartChunk] {
        if let first = entries.first, let last = entries.last {
            let chunkCount = min(1000.0, max(100, Double(entries.count / 8)))
            let chunkSize = (last.date.timeIntervalSinceReferenceDate - first.date.timeIntervalSinceReferenceDate) / chunkCount
            var currentChunkLastDate = first.date + chunkSize
            let chunks: [ChartChunk] = entries.reduce(into: []) {
                if $0.isEmpty {
                    $0.append(.init(range: first.date...currentChunkLastDate))
                } else {
                    while $1.date > currentChunkLastDate {
                        let nextStart = currentChunkLastDate
                        currentChunkLastDate += chunkSize
                        $0.append(.init(range: nextStart...currentChunkLastDate))
                    }
                }
                $0[$0.count - 1].count += 1
            }
            return chunks
        } else {
            return []
        }
    }
}

#Preview {
    PreviewBindingHelper(Date.distantPast...Date.distantFuture) { dateRangeBinding in
        PreviewBindingHelper(FilteredData.previewData()) { data in
            TimelineView(data: data, displayedDateRange: dateRangeBinding)
        }
    }
}
