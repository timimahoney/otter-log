//
//  ColorizeQuery.swift
//  Otter
//
//  Created by Tim Mahoney on 2/13/24.
//

import SwiftUI

public struct Colorization : Codable, Hashable, Sendable, Identifiable {
    public var query: Subquery = .defaultColorizeQuery
    public var color: ColorChoice = .yellow
    public var id = UUID()
    
    public init(
        query: Subquery = .defaultColorizeQuery,
        color: ColorChoice = .yellow
    ) {
        self.query = query
        self.color = color
    }
}

/// A possible choice for a colorized query.
/// We need an enum here to perform some gymnastics in the UI and make it codable easily.
public enum ColorChoice : String, CaseIterable, Codable, Sendable, Hashable {
    case blue
    case indigo
    case purple
    case red
    case orange
    case yellow
    case green
    case brown
    case gray
    case darkGray
}

extension ColorChoice : Identifiable {
    
    var color: Color {
        switch self {
        case .red:       .red
        case .orange:    .orange
        case .yellow:    .yellow
        case .green:     .green
        case .blue:      .blue
        case .indigo:    .indigo
        case .purple:    .purple
        case .brown:     .brown
        case .gray:      .gray
        case .darkGray:  Color(NSColor.darkGray)
        }
    }
    
    var nameKey: LocalizedStringKey {
        switch self {
        case .red:        "Red"
        case .orange:     "Orange"
        case .yellow:     "Yellow"
        case .green:      "Green"
        case .blue:       "Blue"
        case .indigo:     "Indigo"
        case .purple:     "Purple"
        case .brown:      "Brown"
        case .gray:       "Gray"
        case .darkGray:   "Dark Gray"
        }
    }
    
    public var id: String { self.rawValue }
}
