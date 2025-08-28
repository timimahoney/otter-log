//
//  HoverButton.swift
//  Nowaday
//
//  Created by Tim Mahoney on 12/17/23.
//

import SwiftUI

struct HoverButtonStyle : ButtonStyle {
    
    var hoverColor: Color = .accentColor
    var noHoverColor: Color = .accentColor.opacity(0.4)
    var hoverBackground: Color = .clear
    var noHoverBackground: Color = .clear
    
    @State var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let baseTextColor = self.isHovering ? self.hoverColor : self.noHoverColor
        let textColor = configuration.isPressed ? baseTextColor.with(brightness: 0.85) : baseTextColor
        configuration.label
            .onHover { hovering in
                let animation: Animation = self.isHovering ? .easeOut(duration: 0.25) : .easeIn(duration: 0.01)
                withAnimation(animation) {
                    self.isHovering = hovering
                }
            }
            .background(self.self.isHovering ? self.hoverBackground : self.noHoverBackground)
            .foregroundColor(textColor)
    }
}
