//
//  LogLevelQueryView.swift
//  Otter
//
//  Created by Tim Mahoney on 1/21/24.
//

import Foundation
import SwiftUI

// MARK: - Log Level Query

struct LogLevelQueryView : View {
    
    @Binding var query: LogLevelQuery
    var compact: Bool = false
    var delete: (() -> ())?
    
    @State var selectedLevels: Set<OSLogEntryLog.Level> = [ .debug ]
    
    var body: some View {
        
        HStack(spacing: 0) {
            
            LogLevelSegmentedControl(enabledLevels: self.$query.logLevels, compact: self.compact)
            
            if self.compact {
                HStack(alignment: .center, spacing: 0) {
                    self.grabber()
                        .padding(.leading, 4)
                        .padding(.trailing, 2)
                    self.trashButton()
                }
            } else {
                VStack(alignment: .center, spacing: 0) {
                    self.trashButton()
                    self.grabber()
                        .padding(4)
                }
            }
        }
        .padding(0)
        .background(.thickMaterial)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.gray, lineWidth: QueryView.strokeWidth)
        )
        .frame(width: 190)
    }
    
    @ViewBuilder
    func grabber() -> some View {
        Image(systemName: "lines.measurement.horizontal")
            .foregroundStyle(.tertiary.opacity(0.5))
            .imageScale(.small)
            .font(.subheadline)
    }
    
    @ViewBuilder
    func trashButton() -> some View {
        Button {
            self.delete?()
            Analytics.track("Delete Subquery", [
                .analytics_subqueryType: "Levels",
            ])
        } label: {
            Image(systemName: "xmark")
                .padding(4)
        }
        .buttonStyle(HoverButtonStyle(hoverColor: .trashColor, noHoverColor: Color(NSColor.tertiaryLabelColor)))
        .font(.trashFont)
    }
}

struct LogLevelSegmentedControl : View {
    
    @Binding var enabledLevels: Set<OSLogEntryLog.Level>
    var compact: Bool
    
    static let borderColor = Color(NSColor.tertiaryLabelColor)
    static let buttonBorderColor = Self.borderColor.opacity(0.6)
    
    var body: some View {
        if self.compact {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    LevelButton(level: .debug, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.trailing], Self.buttonBorderColor)
                    LevelButton(level: .info, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.leading, .trailing], Self.buttonBorderColor)
                        .padding([.leading, .trailing], -1)
                    LevelButton(level: .notice, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.leading, .bottom], Self.buttonBorderColor)
                        .padding([.leading, .trailing], -1)
                    LevelButton(level: .error, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.leading, .trailing], Self.buttonBorderColor)
                    LevelButton(level: .fault, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.leading], Self.buttonBorderColor)
                        .padding([.leading], -1)
                }
                .border([.trailing], Self.buttonBorderColor)
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    LevelButton(level: .debug, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.trailing, .bottom], Self.buttonBorderColor)
                    LevelButton(level: .info, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.leading, .trailing, .bottom], Self.buttonBorderColor)
                        .padding([.leading], -1)
                    LevelButton(level: .notice, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.leading, .bottom], Self.buttonBorderColor)
                        .padding([.leading], -1)
                }
                HStack(spacing: 0) {
                    LevelButton(level: .error, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.top, .trailing], Self.buttonBorderColor)
                    LevelButton(level: .fault, enabledLevels: self.$enabledLevels, compact: self.compact)
                        .border([.top, .leading], Self.buttonBorderColor)
                        .padding([.leading], -1)
                }
                .padding([.top], -1)
            }
            .border([.trailing], Self.buttonBorderColor)
            .frame(height: 44)
        }
    }
    
    struct LevelButton : View {
        
        var level: OSLogEntryLog.Level
        @Binding var enabledLevels: Set<OSLogEntryLog.Level>
        
        @State var isOn: Bool = false
        @State var isHovering: Bool = false
        var compact: Bool
        
        var body: some View {
            Toggle(isOn: self.$isOn) {
                Text(self.compact ? self.level.compactDescription : self.level.description)
            }
            .toggleStyle(.button)
            .buttonStyle(LevelButtonStyle(isEnabled: self.isOn, isHovering: self.isHovering, compact: self.compact))
            .font(.callout.monospaced())
            .onChange(of: self.isOn) { oldValue, newValue in
                if newValue {
                    self.enabledLevels.insert(self.level)
                } else {
                    self.enabledLevels.remove(self.level)
                }
            }
            .onAppear {
                self.isOn = self.enabledLevels.contains(self.level)
            }
            .onHover { isHovering in
                let animation: Animation = self.isHovering ? .easeOut(duration: 0.25) : .snappy(duration: 0.01)
                withAnimation(animation) {
                    self.isHovering = isHovering
                }
            }
        }
        
        struct LevelButtonStyle : ButtonStyle {
            
            var isEnabled: Bool
            var isHovering: Bool
            var compact: Bool
            
            func makeBody(configuration: Configuration) -> some View {
                ZStack {
                    self.backgroundColor(configuration)
                        
                    configuration.label
                        .foregroundStyle(self.textColor(configuration))
                }
                .frame(height: self.compact ? 24 : 23)
            }
            
            func textColor(_ configuration: Configuration) -> Color {
                if self.isEnabled {
                    if configuration.isPressed {
                        return Color(NSColor.white.blended(withFraction: 0.3, of: NSColor.accent)!)
                    } else if self.isHovering {
                        return .white.opacity(0.95)
                    } else {
                        return .white.opacity(0.9)
                    }
                } else {
                    if configuration.isPressed {
                        return .primary
                    } else if self.isHovering {
                        return .secondary
                    } else {
                        return .secondary
                    }
                }
            }
            
            func backgroundColor(_ configuration: Configuration) -> Color {
                if self.isEnabled {
                    if configuration.isPressed {
                        return Color(NSColor(.accentColor).blended(withFraction: 0.1, of: NSColor.black)!)
                    } else if self.isHovering {
                        return Color(NSColor(.accentColor).blended(withFraction: 0.08, of: NSColor.black)!)
                    } else {
                        return .accentColor
                    }
                } else {
                    if configuration.isPressed {
                        return .secondary.opacity(0.3)
                    } else if self.isHovering {
                        return .secondary.opacity(0.2)
                    } else {
                        return .clear
                    }
                }
            }
        }
    }
}

#Preview {
    PreviewBindingHelper(LogLevelQuery.logLevels([ .error, .info ])) { logQuery in
        LogLevelQueryView(query: logQuery) {
            // Delete!
        }
    }
}
