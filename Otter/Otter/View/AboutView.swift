//
//  AboutView.swift
//  Otter
//
//  Created by Tim Mahoney on 4/22/24.
//

import CoreFoundation
import Foundation
import SwiftUI

struct AboutView : View {
    
    @Environment(\.openURL) private var openURL
    @Environment(\.dismissWindow) private var dismissWindow
    
    static let iconSize: CGFloat = 256
    
    @State var hoverX: CGFloat = 0
    @State var hoverY: CGFloat = 0
    
    var body: some View {

            VStack {
                VStack {
                    Text("Otter Log Console")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 1)
                        .padding(.top, 4)
                        
                    Button("Jolly Code") {
                        if let url = URL(string: "https://jollycode.com") {
                            NSWorkspace.shared.open(url)
                        } else {
                            Logger.ui.fault("Couldn't create jollycode.com URL")
                        }
                    }
                    .buttonStyle(HoverButtonStyle())
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                    
                    Text("Version \(self.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    
                    let rotation = self.hoverX + self.hoverY
                    let hoverTotal = abs(self.hoverX) + abs(self.hoverY)
                    
                    ZStack {
                        Image("otter-appicon")
                            .resizable()
                            .frame(width: Self.iconSize, height: Self.iconSize)
                            .shadow(
                                radius: 1 + pow(hoverTotal * 5, 2),
                                x: -self.hoverX * 15,
                                y: 5 + self.hoverY * 15
                            )
                        
                        self.gradientOverlay(rotation: .degrees(rotation * 360))
                            .blendMode(.colorDodge)
                            .opacity(hoverTotal / 2)
                        
                        self.gradientOverlay(rotation: .degrees(-rotation * 360))
                            .blendMode(.screen)
                            .opacity(hoverTotal / 4)
                            
                    }
                    .padding(.bottom, 12)
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let point):
                            withAnimation(.spring) {
                                self.hoverX = (point.x - (Self.iconSize / 2)) / Self.iconSize
                                self.hoverY = (-(point.y - (Self.iconSize / 2))) / Self.iconSize
                            }
                        case .ended:
                            withAnimation(.bouncy(extraBounce: 0.5)) {
                                self.hoverX = 0
                                self.hoverY = 0
                            }
                        }
                    }
                    .rotation3DEffect(
                        .degrees(self.hoverX * 11),
                        axis: (x: 0, y: 0.5, z: 0)
                    )
                    .rotation3DEffect(
                        .degrees(self.hoverY * 11),
                        axis: (x: 0.5, y: 0, z: 0)
                    )
                    .scaleEffect(CGSize(
                        width: 1 + (hoverTotal * 0.1),
                        height: 1 + (hoverTotal * 0.1)
                    ))
                    
                    VStack(spacing: 8) {
                        HStack(spacing: 1) {
                            Text("Otter loads log archives from the unified logging system, ")
                            
                            Button("OSLog") {
                                if let url = URL(string: "https://developer.apple.com/documentation/os/logging") {
                                    self.openURL(url)
                                } else {
                                    Logger.ui.fault("Unable to create URL for logging system website")
                                }
                            }
                            .buttonStyle(HoverButtonStyle(
                                hoverColor: .accent.with(saturation: 1.3, brightness: 0.8),
                                noHoverColor: .accent
                            ))
                            .fontDesign(.monospaced)
                            .fontWeight(.bold)
                        }
                        
                        HStack(spacing: 1) {
                            Text("You can get a log archive from a ")
                            
                            Button("sysdiagnose") {
                                if let url = URL(string: "https://it-training.apple.com/tutorials/support/sup075") {
                                    self.openURL(url)
                                } else {
                                    Logger.ui.fault("Unable to create URL for sysdiagnose website")
                                }
                            }
                            .buttonStyle(HoverButtonStyle(
                                hoverColor: .accent.with(saturation: 1.3, brightness: 0.8),
                                noHoverColor: .accent
                            ))
                            .fontDesign(.monospaced)
                            .fontWeight(.bold)
                        }
                        
                        HStack(spacing: 1) {
                            Text("You can also generate one by running ")
                            
                            Button("log collect") {
                                if let url = URL(string: "x-man-page://log") {
                                    self.openURL(url)
                                } else {
                                    Logger.ui.fault("Unable to create URL for log collect")
                                }
                            }
                            .buttonStyle(HoverButtonStyle(
                                hoverColor: .accent.with(saturation: 1.3, brightness: 0.8),
                                noHoverColor: .accent
                            ))
                            .fontDesign(.monospaced)
                            .fontWeight(.bold)
                        }
                    }
                    .padding(.bottom, 12)
                    
                    Button {
                        self.dismissWindow()
                        Task.detached(priority: .userInitiated) {
                            await MainActor.run {
                                NSDocumentController.shared.openDocument(nil)
                            }
                        }
                    } label: {
                        Text("Enjoy")
                            .padding([.top, .bottom], 4)
                            .padding([.leading, .trailing], 8)
                            .font(.title3)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(ColorizeButtonStyle(colorful: true, backgroundColor: .accent))
                    .padding(.bottom, 10)
                }
                .padding(16)
                .cornerRadius(8)
            }
            .padding([.leading, .trailing], 16)
            .fixedSize()
    }
    
    @ViewBuilder
    func gradientOverlay(rotation: Angle) -> some View {
        Rectangle()
            .fill(
                AngularGradient(
                    colors: [.white, .black, .white, .black, .white],
                    center: .center,
                    angle: rotation
                )
            )
            .frame(width: Self.iconSize, height: Self.iconSize)
            .mask {
                Image("otter-appicon")
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
            }
    }
    
    var version: String = {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        } else {
            return String(localized: "Unknown")
        }
    }()
}

#Preview {
    AboutView()
}
