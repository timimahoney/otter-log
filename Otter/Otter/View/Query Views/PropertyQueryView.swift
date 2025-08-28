//
//  PropertyQueryView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/22/24.
//

import SwiftUI

struct PropertyQueryView : View {
    
    static let popupProperties: [PropertyQuery.Property] = [
        .message,
        .subsystem,
        .category,
        .process,
        .pid,
        .sender,
        .activity,
        .thread,
    ]
    
    static let popupComparisons: [PropertyQuery.Comparison] = [
        .contains,
        .equals,
        .doesNotContain,
        .doesNotEqual,
    ]
    
    @Binding var query: PropertyQuery
    @State var isTextFieldSelected: Bool = false
    var compact: Bool = false
    var delete: (() -> ())?
    
    static let cornerRadius: CGFloat = 6
    
    var body: some View {
        
        let fillColor = self.query.property.fillColor
        
        if self.compact {
            
            //
            // Compact
            //
            HStack(spacing: 0) {
                self.propertyComparisonSelectorView()
                    .frame(width: 24)
                self.filterTextField()
                    .frame(width: 120)
                self.trashButton()
                    .frame(width: 20)
            }
            .padding(.trailing, 1)
            .padding(.leading, 4)
            .padding([.top, .bottom], 2)
            .background(fillColor.with(saturation: 0.9, brightness: 0.9), in: Rectangle())
            .cornerRadius(Self.cornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(fillColor.with(saturation: 1, brightness: 0.7), lineWidth: QueryView.strokeWidth)
            }
        } else {
            
            //
            // Non-Compact
            //
            VStack(spacing: 1) {
                
                // Top row
                HStack(spacing: 0) {
                    self.propertyComparisonSelectorView()
                    Spacer()
                    self.grabber()
                    self.trashButton()
                        .padding(.trailing, 5)
                        .padding(.leading, 8)
                }
                
                // Filter
                self.filterTextField()
                    .padding([.leading, .trailing], 3)
                    .padding(.bottom, 1)
            }
            .padding([.top, .bottom], 2)
            .frame(width: 144)
            .background(fillColor.with(saturation: 0.9, brightness: 0.9), in: Rectangle())
            .cornerRadius(Self.cornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(fillColor.with(saturation: 1, brightness: 0.7), lineWidth: QueryView.strokeWidth)
            }
        }
    }
    
    @ViewBuilder
    func propertyComparisonSelectorView() -> some View {
        //
        // Property
        //
        Menu {
            ForEach(Self.popupProperties) { property in
                Button {
                    self.query.property = property
                    
                    Analytics.track("Select Property", [
                        .analytics_property: property.name,
                    ])
                } label: {
                    Toggle(isOn: .constant(self.query.property == property)) {
                        Text(property.name)
                    }
                }
            }
            
            Divider()
            
            ForEach(Self.popupComparisons) { comparison in
                Button {
                    self.query.comparison = comparison
                    Analytics.track("Select Comparison", [
                        .analytics_comparison: comparison.analyticsSymbol,
                    ])
                } label: {
                    Toggle(isOn: .constant(self.query.comparison == comparison)) {
                        Text(comparison.nameKey)
                    }
                }
            }
        } label: {
            Text(self.attributedPropertyComparisonString())
                .foregroundColor(self.query.property.textColor)
                .font(.headline.smallCaps().monospaced())
        }
        .frame(alignment: .leading)
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.accessoryBar)
        .accessibilityHint("Change filtered property")
    }
    
    func attributedPropertyComparisonString() -> AttributedString {
        // We want to show the name plus the comparison symbol next to each other in the same view.
        // However, we want some extra spacing in between them.
        // Sadly, a space character is too big.
        // So, let's use some kerning.
        var attributes = AttributeContainer()
        let baseName: String
        if self.compact {
            attributes.kern = 2
            baseName = self.query.property.compactName
        } else {
            attributes.kern = 4
            baseName = self.query.property.name
        }
        
        // The last letter of the name needs to have the kerning.
        // But we don't want ALL the letters to have the extra kerning.
        var result = AttributedString(baseName.dropLast(1))
        let lastCharacter = AttributedString(baseName.suffix(1), attributes: attributes)
        result.append(lastCharacter)
        
        // Also fix the baseline offset for some symbols.
        attributes.baselineOffset = self.query.comparison.baselineOffset
        let symbol = AttributedString(self.query.comparison.symbol, attributes: attributes)
        result.append(symbol)
        
        return result
    }
    
    @ViewBuilder
    func filterTextField() -> some View {
        //
        // Filter Text Field
        //
        let prompt = self.compact ? "Colorize" : "Filter"
        TextField(prompt, text: self.$query.value)
            .font(.subheadline.monospaced())
            .textFieldStyle(.plain)
            .padding(.init(top: 3, leading: 6, bottom: 3, trailing: 6))
            .background(in: RoundedRectangle(cornerRadius: 6))
    }
    
    @ViewBuilder
    func trashButton() -> some View {
        Button {
            let query = self.query
            self.delete?()
            Analytics.track("Delete Subquery", [
                .analytics_subqueryType: query.property.name,
                .analytics_filterStringSize: query.value.count,
            ])
        } label: {
            Image(systemName: "xmark")
                .font(.trashFont)
        }
        .buttonStyle(HoverButtonStyle(hoverColor: .trashColor, noHoverColor: .primary.opacity(0.3)))
    }
    
    @ViewBuilder
    func grabber() -> some View {
        Image(systemName: self.compact ? "lines.measurement.vertical" : "lines.measurement.horizontal")
            .foregroundStyle(.tertiary)
            .imageScale(.small)
            .font(.subheadline)
    }
}

extension PropertyQuery.Property {
    
    var textColor: Color {
        switch self {
        case .subsystem:     .white
        case .category:      .white
        case .message:       .white
        case .process:       .white
        case .pid:           .white
        case .sender:        .white
        case .activity:      .white
        case .thread:        .white
        }
    }
    
    var fillColor: Color {
        switch self {
        case .subsystem:     .blue
        case .category:      .indigo
        case .message:       .green
        case .process:       .orange
        case .pid:           .brown
        case .sender:        .yellow
        case .activity:      .red
        case .thread:        .purple
        }
    }
}

extension PropertyQuery.Comparison {
    
    var font: Font {
        switch self {
        case .contains:         .title2.weight(.regular).monospaced()
        case .equals:           .headline.weight(.bold).monospaced()
        case .doesNotContain:   .title2.weight(.regular).monospaced()
        case .doesNotEqual:     .title2.weight(.regular).monospaced()
        }
    }
    
    // We need a tiny bit extra baseline offset on some symbols because they're weird.
    var baselineOffset: CGFloat {
        switch self {
        case .contains:         0.5
        case .equals:           0
        case .doesNotContain:   0
        case .doesNotEqual:     0
        }
        
    }
    
    var nameKey: LocalizedStringKey {
        switch self {
        case .contains:         "Contains"
        case .equals:           "Equals"
        case .doesNotContain:   "Does Not Contain"
        case .doesNotEqual:     "Does Not Equal"
        }
    }
}

#Preview {
    PreviewBindingHelper(PropertyQuery.contains(.subsystem, "")) { query in
        PropertyQueryView(query: query, delete: {
            // Delete!
        })
    }
}
