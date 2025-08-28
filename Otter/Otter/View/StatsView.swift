//
//  StatsView.swift
//  Otter
//
//  Created by Tim Mahoney on 2/6/24.
//

import Foundation
import SwiftUI

struct StatsView : View {

    @Binding var data: FilteredData
    @Binding var queryProgress: Progress?
    @Binding var loadingProgress: Progress?
    
    static let height: CGFloat = 22
    
    var body: some View {
        StatsInnerView(
            data: self.$data,
            queryProgress: self.$queryProgress,
            loadingProgress: self.$loadingProgress
        )
        .padding(3)
        .frame(height: StatsView.height)
        .foregroundStyle(.tertiary)
        .overlay {
            RoundedRectangle(cornerRadius: StatsView.height)
                .stroke(.tertiary, lineWidth: 1)
        }
        .frame(height: StatsView.height)
    }
}

struct StatsInnerView : View {
    
    @Binding var data: FilteredData
    @Binding var queryProgress: Progress?
    @Binding var loadingProgress: Progress?
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 0) {
            
            let queryProgress = self.queryProgress
            if let queryProgress {
                ProgressView(queryProgress)
                    .labelsHidden()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
                    .padding(.leading, -4)
                    .padding(.trailing, 6)
            }
            
            let entryCount = self.data.entries.count
            Text(verbatim: entryCount.formatted())
                .foregroundStyle(.primary)
                .padding(.leading, 2)
                .padding(.trailing, 2)
            
            if let loadingProgress {
                Text("Loading")
                    .padding(.leading, 8)
                ProgressView(loadingProgress)
                    .labelsHidden()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .padding(.leading, 8)
                    .padding(.trailing, -4)
            }
        }
        .font(.caption.monospaced())
        .padding([.top, .bottom], 4)
        .padding([.leading, .trailing], 4)
    }
}

#Preview {
    PreviewBindingHelper(FilteredData.previewData()) { data in
        
        HStack {
            StatsView(
                data: .constant(FilteredData(Database())),
                queryProgress: .constant(nil),
                loadingProgress: .constant(Progress())
            )
            .padding(8)
            
            StatsView(
                data: data,
                queryProgress: .constant(nil),
                loadingProgress: .constant(nil)
            )
            .padding(8)
            
            StatsView(
                data: data,
                queryProgress: .constant(Progress(totalUnitCount: 3)),
                loadingProgress: .constant(nil)
            )
            .padding(8)
            
            StatsView(
                data: data,
                queryProgress: .constant(nil),
                loadingProgress: .constant(Progress(totalUnitCount: 3))
            )
            
            StatsView(
                data: data,
                queryProgress: .constant(Progress(totalUnitCount: 3)),
                loadingProgress: .constant(Progress(totalUnitCount: 3))
            )
            .padding(8)
        }
    }
}
