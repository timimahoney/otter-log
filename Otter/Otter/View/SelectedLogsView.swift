//
//  SelectedLogsView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/16/24.
//

import Foundation
import SwiftUI

struct SelectedLogsView : View {
    
    @Binding var selectedEntries: [Entry]
    
    static let padding = 16.0
    
    var body: some View {
        let hasSelection = !self.selectedEntries.isEmpty
        if !hasSelection {
            Text("No selection")
                .textSelection(.enabled)
                .font(.subheadline.monospaced())
                .multilineTextAlignment(.leading)
                .foregroundStyle(.tertiary)
                .padding(.all, Self.padding)
                .padding(.bottom, Self.padding * 2)
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
                .background()
        } else {
            ScrollView([.vertical]) {
                VStack {
                    Text("\(self.selectedEntries.count) selected")
                        .textSelection(.enabled)
                        .font(.subheadline.monospaced())
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding([.bottom], 4)
                    let maxLogCount = 100
                    let subset = self.selectedEntries.prefix(maxLogCount)
                    let text = subset.map { $0.message }.joined(separator: "\n")
                    Text(text)
                        .textSelection(.enabled)
                        .font(.subheadline.monospaced())
                        .multilineTextAlignment(.leading)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    let remainingCount = self.selectedEntries.count - subset.count
                    if remainingCount > 0 {
                        HStack {
                            Text("\(remainingCount.formatted()) more…")
                                .textSelection(.disabled)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding([.top], 4)
                            Spacer()
                        }
                    }
                }
                .padding([.all], Self.padding)
            }
            .padding(0)
            .background()
        }
    }
}
