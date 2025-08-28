//
//  CompoundQueryView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/22/24.
//

import SwiftUI

struct CompoundQueryView : View {
    
    @Binding var query: CompoundQuery
    @Binding var topLevelQuery: CompoundQuery
    @Binding var color: ColorChoice
    var showColorPicker: Bool = false
    @FocusState var focusedSubquery: Subquery?
    var compact: Bool = false
    var delete: (() -> ())?
    
    // I can't figure out how to put a hover button into a Menu label.
    // For now, do this disgusting thing out here.
    @State var isHoveringPlus = false
    
    var body: some View {
        let isTopLevel = self.query == self.topLevelQuery
        
        HStack(spacing: 0) {
            
            HStack(alignment: .center, spacing: 0) {
                
                //
                // Color Picker
                //
                if self.showColorPicker {
                    ColorPickerButton(color: self.$color)
                        .padding(.leading, 2)
                        .padding(.trailing, 2)
                }
                
                //
                // And/Or button and Grabber
                //
                if self.compact {
                    self.variantButton()
                        .padding([.leading, .trailing], 1)
                    self.addSubqueryButton()
                        .frame(width: 16, height: 20)
                        .offset(y: -0.5)
                } else {
                    VStack {
                        self.variantButton()
                            .offset(x: self.query.variant == .and ? 0.5 : 0) // just a little nudge in the right direction...
                        self.addSubqueryButton()
                            .offset(x: 1.5, y: -2) // because life is hard
                            .frame(height: 12)
                    }
                }
            }
            .padding([.top, .bottom], self.compact ? 2 : 4)
            .padding([.leading, .trailing], self.compact ? 2 : 4)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.tertiary.opacity(0.12))
                    .stroke(.tertiary.opacity(0.3))
            }
            .padding([.top, .bottom], self.compact ? 2 : 4)
            .padding(.leading, self.compact ? 3 : 6.5)
            .padding(.trailing, self.compact ? 2 : 4)
            
            //
            // Subqueries
            //
            let subqueryPadding: CGFloat = self.compact ? 2 : 2
            HStack(spacing: 0) {
                ForEach(self.$query.subqueries) { $subquery in
                    QueryView(
                        query: $subquery,
                        parent: self.$query,
                        topLevelQuery: self.$topLevelQuery,
                        compact: self.compact,
                        delete: {
                            // TODO: Re-enable animations. For now, they're causing crashes.
//                            withAnimation(.otter) {
                                self.query.removeSubquery(subquery)
//                            }
                        }
                    )
                }
            }
            .padding([.top, .bottom], subqueryPadding)
            
            self.deleteButton()
        }
        .padding([.top, .bottom], 1)
        .padding(.trailing, 4)
        .background(self.query.variant.fillColor, in: Rectangle())
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    self.query.variant.borderStyle(isTopLevel: isTopLevel),
                    style: .init(
                        lineWidth: self.query.variant.borderWidth,
                        dash: self.query.variant.borderDashes
                    )
                )
        )
    }
    
    @ViewBuilder
    func grabber() -> some View {
        Image(systemName: "lines.measurement.horizontal")
            .padding([.top, .bottom], 1)
            .foregroundStyle(.tertiary.opacity(0.5))
            .imageScale(.small)
            .font(.subheadline)
    }
    
    @ViewBuilder
    func deleteButton() -> some View {
        if let deleteAction = self.delete {
            Button {
                let query = self.query
                deleteAction()
                Analytics.track("Delete Subquery", [
                    .analytics_subqueryType: query.variant.analyticsSymbol,
                ])
            } label: {
                Image(systemName: "xmark")
                    .padding(2)
            }
            .buttonStyle(HoverButtonStyle(hoverColor: .trashColor, noHoverColor: .secondary))
            .font(.trashFont)
        }
    }
    
    @ViewBuilder
    func variantButton() -> some View {
        let variant = self.query.variant
        let font: Font = variant == .or ? .caption : (self.compact ? .subheadline : .headline)
        let weight: Font.Weight = self.compact ? .black : (variant == .and ? .bold : .black)
        
        Button(self.compact ? variant.symbolLocalized : variant.symbolLocalized) {
            switch self.query.variant {
            case .and:
                self.query.variant = .or
            case .or:
                self.query.variant = .and
            }
        }
        .accessibilityHint("Change compound filter variant")
        .buttonStyle(HoverButtonStyle(noHoverColor: .primary.opacity(0.5)))
        .font(font.smallCaps().monospaced().weight(weight))
        .frame(height: 16)
        .frame(width: 20)
    }
    
    @ViewBuilder
    func addSubqueryButton() -> some View {
        //
        // Add subquery button
        //
        Menu {
            Text("Property")
            
            ForEach(PropertyQuery.Property.allCases) { property in
                Button(property.name) {
                    // TODO: Re-enable animations. For now, they're causing crashes.
//                    withAnimation(.otter) {
                        let newSubquery = Subquery.contains(property, "")
                        self.focusedSubquery = newSubquery
                        self.query.addSubquery(newSubquery)
                        Analytics.track("Add Property Subquery", [
                            .analytics_property: property.name,
                        ])
//                    }
                }
            }
            
            Button("Level") {
                // TODO: Re-enable animations. For now, they're causing crashes.
//                withAnimation(.otter) {
                    let newSubquery = Subquery.logLevel([])
                    self.query.addSubquery(newSubquery)
                    Analytics.track("Add Level Subquery")
//                }
            }
            
            Divider()
            
            Text("Compound")
            
            ForEach(CompoundQuery.Variant.allCases) { variant in
                Button(variant.localizedStringKey) {
                    // TODO: Re-enable animations. For now, they're causing crashes.
//                    withAnimation(.otter) {
                        
                        // When creating a new compound subquery, make sure to add at least one sub-sub-query.
                        let subsub: Subquery = .contains(.message)
                        
                        let newSubquery: Subquery = .compound(CompoundQuery(variant: variant, subqueries: [subsub]))
                        self.query.addSubquery(newSubquery)
                        Analytics.track("Add Compound Subquery", [
                            .analytics_compoundVariant: variant.analyticsSymbol,
                        ])
//                    }
                }
            }
        } label: {
            Text("+")
                .font(.title2.weight(.semibold))
                .foregroundStyle(self.isHoveringPlus ? Color.accentColor : .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityHint("Add sub query")
        .padding(0)
        .onHover { newValue in
            self.isHoveringPlus = newValue
        }
    }
}

// MARK: - Strings

extension CompoundQuery.Variant {
    
    var localizedStringKey: LocalizedStringKey {
        switch self {
        case .and:   "All"
        case .or:    "Any"
        }
    }
    
    var textColor: Color {
        switch self {
        case .and:   .black.opacity(0.4)
        case .or:    .black.opacity(0.4) //.white.opacity(0.9)
        }
    }
    
    var textHoverColor: Color {
        switch self {
        case .and:   .black.opacity(0.6)
        case .or:    .black.opacity(0.6) // .white.opacity(0.4)
        }
    }
    
    var fillColor: Color {
        switch self {
        case .and:   Color(NSColor.controlBackgroundColor)
        case .or:    Color(NSColor.controlBackgroundColor)
        }
    }
    
    func borderStyle(isTopLevel: Bool) -> Color {
        return isTopLevel ? Color(NSColor.tertiaryLabelColor) : .secondary
    }
    
    var borderWidth: CGFloat {
        switch self {
        case .and:   1
        case .or:    1
        }
    }
    
    var borderDashes: [CGFloat] {
        switch self {
        case .and:   []
        case .or:    [4, 2]
        }
    }
}
