//
//  ColorizeButtonStyle.swift
//  Otter
//
//  Created by Tim Mahoney on 2/20/24.
//

import SwiftUI

struct ColorizeButtonStyle: ButtonStyle {
    
    var colorful: Bool = true
    var backgroundColor: Color = .clear
    var cornerRadius: CGFloat = 6
    
    @State private var isHovering: Bool = false
    
    static let gradientRepetition = 10
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label
            
            let showWhiteLabel = self.isHovering && self.colorful
            if showWhiteLabel {
                configuration.label
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 0, y: -0.75)
                    .shadow(color: .white.opacity(0.3), radius: 0, y: 0.75)
            }
        }
        .padding([.leading, .trailing], 4)
        .padding([.top, .bottom], 1.0)
        .onHover { hovering in
            if self.colorful {
                if hovering {
                    withAnimation(.smooth(duration: 0.2, extraBounce: 0.5)) {
                        self.isHovering = true
                    }
                } else {
                    withAnimation(.otter) {
                        self.isHovering = false
                    }
                }
            } else {
                withAnimation(.otter) {
                    self.isHovering = hovering
                }
            }
        }
        .background {
            GeometryReader { reader in
                let gradientSize = reader.size.width * CGFloat(Self.gradientRepetition)
                let pressedOffset = configuration.isPressed ? (reader.size.width * 1 / 16) : 0
                let fillOffset = pressedOffset + (self.isHovering ? -reader.size.width * 2 : reader.size.width)
                let strokeOffset = pressedOffset + (self.isHovering ? -reader.size.width / 2 : -reader.size.width * 2)
                
                if self.colorful {
                    
                    if !self.isHovering {
                        self.backgroundColor
                    }
                    
                    // Stroke
                    RoundedRectangle(cornerRadius: self.cornerRadius)
                        .fill(self.coolGradient(reversed: false).opacity(self.isHovering ? 1 : 0))
                        .frame(width: gradientSize)
                        .offset(x: strokeOffset)
                    
                    // White Border
                    RoundedRectangle(cornerRadius: self.cornerRadius)
                        .fill(.white.opacity(self.isHovering ? 1 : 0))
                        .stroke(self.isHovering ? Color(NSColor.tertiaryLabelColor) : Color.clear)
                    
                    // Gradient fill
                    ZStack {
                        RoundedRectangle(cornerRadius: self.cornerRadius)
                            .inset(by: 2)
                            .fill(self.coolGradient(reversed: true))
                            .frame(width: self.isHovering ? gradientSize : 0)
                            .offset(x: fillOffset)
                    }
                    .frame(width: reader.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius).inset(by: 2))
                    .overlay {
                        RoundedRectangle(cornerRadius: self.cornerRadius)
                            .inset(by: 2)
                            .stroke(.black.opacity(0.3))
                    }
                    .opacity(self.isHovering ? 1 : 0)
                }
                
                // Plain border (non-hovering)
                // Plus non-color hover fill
                RoundedRectangle(cornerRadius: self.cornerRadius)
                    .fill(self.isHovering && !self.colorful ? .primary.opacity(0.05) : Color.clear)
                    .stroke(.secondary.opacity(0.4), lineWidth: 1.5)
                
                // Pressed state
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: self.cornerRadius)
                        .inset(by: self.colorful ? 2 : 0)
                        .fill(.black.opacity(0.14))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius))
    }
    
    func coolGradient(reversed: Bool) -> LinearGradient {
        let baseColors: [Color]
        if self.colorful {
            baseColors = [ .green, .yellow, .orange, .red, .purple, .blue ]
        } else {
            baseColors = [ .black.opacity(0.2), .black.opacity(0.1) ]
        }
        
        let repetitionCount = Self.gradientRepetition
        let allColors = (0..<repetitionCount).flatMap { _ in baseColors }
        let colors = reversed ? allColors.reversed() : allColors
        
        // We want a "gradient" that is really just multiple colors one after another.
        // Let's add a stop at the beginning and end of each color.
        let colorSize = (1.0 / CGFloat(colors.count))
        let stops: [Gradient.Stop] = colors.enumerated().flatMap {
            let start = (CGFloat($0.offset) * colorSize)
            let end = start + colorSize - 0.0001
            return [
                Gradient.Stop(color: $0.element, location: start),
                Gradient.Stop(color: $0.element, location: end),
            ]
        }
        
        return LinearGradient(
            stops: stops,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Preview

#Preview {
    HStack {
        Button("Save Query")  {
            // yay!
        }
        .buttonStyle(ColorizeButtonStyle(colorful: false))
        
        Button("Colorize") {
            // yay!
        }
        .buttonStyle(ColorizeButtonStyle())
        
        Button("Background") {
            // yay!
        }
        .buttonStyle(ColorizeButtonStyle(backgroundColor: .accent))
        
        Button {
            // yay
        } label: {
            Image(systemName: "plus")
                .fontWeight(.bold)
                .font(.headline)
                .padding(4)
        }
        .buttonStyle(ColorizeButtonStyle())
        .foregroundColor(.secondary)
    }
    .padding(10)
    .frame(width: 300)
}
