//
//  ColorPickerButton.swift
//  Otter
//
//  Created by Tim Mahoney on 2/13/24.
//

import SwiftUI

struct ColorPickerButton : View {
    
    @Binding var color: ColorChoice
    var action: (() -> ())?
    
    @State var isShowingPopover = false
    
    var body: some View {
        
        ColorChoiceButton(titleKey: "Choose color", color: self.$color) {
            self.isShowingPopover = !self.isShowingPopover
            Analytics.track("Open Colorization Color Picker")
        }
        .popover(isPresented: self.$isShowingPopover) {
            HStack {
                ForEach(ColorChoice.allCases) { color in
                    ColorChoiceButton(titleKey: color.nameKey, color: .constant(color)) {
                        withAnimation(.otter) {
                            self.color = color
                            self.isShowingPopover = !self.isShowingPopover
                        }
                        
                        Analytics.track("Choose Color", [ .analytics_colorizationName : color.rawValue ])
                    }
                }
            }
            .padding([.leading, .trailing], 4)
            .padding([.top, .bottom], 4)
        }
    }
}

struct ColorChoiceButton : View {
    
    var titleKey: LocalizedStringKey
    @Binding var color: ColorChoice
    var action: (() -> ())?
    
    @State var isHovering = false
    
    var body: some View {
        Button(self.titleKey) {
            self.action?()
        }
        .buttonStyle(ColorPickerButtonStyle(color: self.color.color, isHovering: self.$isHovering))
        .onHover { hovering in
            let animation: Animation = hovering ? .snappy(duration: 0.1) : .easeIn(duration: 0.3)
            withAnimation(animation) {
                self.isHovering = hovering
            }
        }
    }
}

struct ColorPickerButtonStyle : ButtonStyle {
    
     var color: Color
    @Binding var isHovering: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .fill(self.outerFillColor(configuration: configuration))
                .frame(width: 16, height: 16)
            Circle()
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(width: 12, height: 12)
            Circle()
                .fill(self.innerFillColor(configuration: configuration))
                .frame(width: 10, height: 10)
        }
    }
    
    func outerFillColor(configuration: Configuration) -> Color {
        if self.isHovering {
            if configuration.isPressed {
                return self.color.with(saturation: 0.8, brightness: 0.65)
            } else {
                return self.color.with(saturation: 1, brightness: 0.8)
            }
        } else {
            if configuration.isPressed {
                return self.color.with(saturation: 0.8, brightness: 1.6)
            } else {
                return self.color.with(saturation: 0.8, brightness: 0.8)
            }
        }
    }
    
    func innerFillColor(configuration: Configuration) -> Color {
        if self.isHovering {
            if configuration.isPressed {
                return self.color.with(saturation: 0.6, brightness: 1.12)
            } else {
                return self.color.with(saturation: 0.9, brightness: 1.1)
            }
        } else {
            if configuration.isPressed {
                return self.color.with(saturation: 0.8, brightness: 1.12)
            } else {
                return self.color
            }
        }
    }
}
