//
//  Utilities.swift
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Objective-C Exceptions

public struct NSExceptionError : Swift.Error, @unchecked Sendable {

   public let exception: NSException

   public init(exception: NSException) {
      self.exception = exception
   }
}

public func rethrowNSExceptions(_ workItem: () -> Void) throws {
    let exception = OtterExecuteWithObjCExceptionHandling {
        workItem()
    }
    if let exception = exception {
        throw NSExceptionError(exception: exception)
    }
}

// MARK: - Array / Sequence

extension Array {
    
    public subscript(indexSet: IndexSet) -> [Element] {
        return indexSet.map { self[$0] }
    }
    
    /// This is very finicky. It essentially assumes that the list is a sorted list of things that can be greater or less than each other.
    public func ot_binaryFirstIndex(where block: (Element) throws -> Bool) rethrows -> Index? {
        return try self.ot_binaryFirstIndexFromLeft(start: self.startIndex, end: self.endIndex, where: block)
    }
    
    private func ot_binaryFirstIndexFromLeft(start: Index, end: Index, where block: (Element) throws -> Bool) rethrows -> Index? {
        let size = end - start
        if size == 0 {
            return nil
        }
        
        // We start from the left, so if this matches, then we're done.
        let leftElement = self[start]
        let leftMatches = try block(leftElement)
        if leftMatches {
            return start
        } else if size == 1 {
            return nil
        }
        
        // The left doesn't match. Let's check the middle to see if we need to look in the first half or the last.
        let middle = start + (size / 2)
        let middleElement = self[middle]
        let middleMatches = try block(middleElement)
        
        // If the middle is a match and the middle is actually the end, then the middle is the match.
        if middleMatches && (middle - 1 == end) {
            return middle
        }
        
        if !middleMatches {
            // The middle doesn't match, so we need to check the second half of the range
            if let rightIndex = try self.ot_binaryFirstIndexFromLeft(start: middle + 1, end: end, where: block) {
                return rightIndex
            }
        }
        
        // Try the left half.
        let nextLowerBound = start + 1
        if let leftOfMiddleIndex = try self.ot_binaryFirstIndexFromLeft(start: nextLowerBound, end: middle, where: block) {
            return leftOfMiddleIndex
        } else if middleMatches {
            return middle
        } else {
            return nil
        }
    }
    
    func ot_concurrentFilter(where block: @escaping (Element) -> Bool) -> [Element] {
        let batchCount = 32
        let batchSize = Swift.max(self.count / batchCount, 100)
        let batchStarts = stride(from: 0, to: self.count, by: batchSize).map { $0 }
        
        let filteredBatchesLock = OSAllocatedUnfairLock<[Int : [Element]]>(initialState: [:])
        DispatchQueue.concurrentPerform(iterations: batchStarts.count) { i in
            let batchStart = batchStarts[i]
            let batchEnd = Swift.min(batchStart + batchSize, self.count)
            let batch = Array(self[batchStart..<batchEnd])
            let filtered = batch.filter(block)
            filteredBatchesLock.withLock { $0[i] = filtered }
        }
        
        let sortedBatches = filteredBatchesLock.withLock { $0 }.enumerated().sorted { $0.element.key < $1.element.key }
        let matches = sortedBatches.flatMap { $0.element.value }
        return matches
    }
}

// MARK: - UI

extension Color {
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func with(hue huePercent: CGFloat = 1, saturation saturationPercent: CGFloat = 1, brightness brightnessPercent: CGFloat = 1, alpha alphaPercent: CGFloat = 1) -> Color {
        let nsColor = NSColor(self)
        var hue = CGFloat(0.0)
        var saturation = CGFloat(0.0)
        var brightness = CGFloat(0.0)
        var alpha = CGFloat(0.0)
        if let properColor = nsColor.usingColorSpace(.deviceRGB) {
            properColor.getHue(&hue, saturation: &saturation, brightness:&brightness, alpha:&alpha)
        }
        
        hue *= huePercent
        saturation *= saturationPercent
        brightness *= brightnessPercent
        alpha *= alphaPercent
        let newColor = Color(hue: hue, saturation: saturation, brightness: brightness)
        
        return newColor
    }

    static let trashColor: Color = .red.with(brightness: 2).opacity(0.8)
}

extension Font {
    
    static let trashFont: Font = .caption.weight(.black)
}

extension Animation {
    
    static let otter: Animation = .snappy(duration: 0.2)
}

/// This is the greatest of hacks.
/// We send it through `sendAction` in order to pass around an `NSTextFinder.Action`.
class TextFinderAction : NSObject {
    
    let action: NSTextFinder.Action
    
    @objc func tag() -> Int { self.action.rawValue }
    
    init(_ action: NSTextFinder.Action) {
        self.action = action
    }
}

// MARK: - Time / Date

extension Date {
    
    /// Returns a properly formatted string for a date.
    ///
    /// The standard DateFormatter doesn't support microseconds, but microseconds are pretty important for logging.
    /// As a result, we can't just use a single date formatter. We have to do something funky.
    static func otterDateString(_ date: Date, includeMicroseconds: Bool = true) -> String {
        if includeMicroseconds {
            // The standard DateFormatter doesn't support microseconds, so we have to be funky.
            let firstPart = Self.firstPartDateFormatter.string(from: date)
            let nanoseconds = Calendar.current.component(.nanosecond, from: date)
            let microsecondsString = String(format: "%06d", nanoseconds / 1000)
            let timeZone = Self.timeZoneDateFormatter.string(from: date)
            return "\(firstPart).\(microsecondsString)\(timeZone)"
        } else {
            return self.noMicrosecondsDateFormatter.string(from: date)
        }
    }
    
    static let noMicrosecondsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZ"
        return formatter
    }()
    
    static let firstPartDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    static let timeZoneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ZZZ"
        return formatter
    }()
    
    var secondsSinceNowString: String { (-self.timeIntervalSinceNow).secondsString }
}

extension ClosedRange<Date> {   
    public static let distantRange = Date.distantPast...Date.distantFuture
    
    public var timeInterval: TimeInterval { self.upperBound.timeIntervalSince(self.lowerBound) }
}

extension TimeInterval {
    public var secondsString: String { String(format: "%.2fs", self) }
}

// MARK: - EdgeBorder

extension View {
    func border(_ edges: [Edge], _ color: Color) -> some View {
        overlay(EdgeBorder(width: 1, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        edges.map { edge -> Path in
            switch edge {
            case .top: return Path(.init(x: rect.minX, y: rect.minY, width: rect.width, height: width))
            case .bottom: return Path(.init(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width))
            case .leading: return Path(.init(x: rect.minX, y: rect.minY, width: width, height: rect.height))
            case .trailing: return Path(.init(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height))
            }
        }.reduce(into: Path()) { $0.addPath($1) }
    }
}

// MARK: NSItemProvider

extension DropInfo {
    
    // Because that shit is just insanely shit.
    func transferrables<T : Transferable>(for utType: UTType) -> [T] {
        let lock = OSAllocatedUnfairLock<[Int : T]>(initialState: [:])
        let group = DispatchGroup()
        let itemProviders = self.itemProviders(for: [utType])
        for (i, provider) in itemProviders.enumerated() {
            group.enter()
            // TODO: Progress?
            _ = provider.loadTransferable(type: T.self) { result in
                switch result {
                case .success(let object):
                    lock.withLock { $0[i] = object }
                case .failure(let error):
                    Logger.ui.error("Failed to load \(T.self) when dropping: \(error)")
                }
                group.leave()
            }
        }
        
        group.wait()
        
        let objects = lock.withLock { $0 }.sorted { $0.key < $1.key }.map { $0.value }
        return objects
    }
}

// MARK: - Concurrency

/// Because sometimes you just gotta get shit done.
struct SendableWrapper<T> : @unchecked Sendable {
    var object: T
}

func asyncAntipattern(_ block: @escaping () async throws -> ()) rethrows {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        try await block()
        semaphore.signal()
    }
    semaphore.wait()
}

// MARK: - OSLog

extension OSLogStore {
    
    func entryDateRange() throws -> ClosedRange<Date>? {
        let end = try self.lastEntryDate()
        let start = try self.firstEntryDate()
        if let start, let end {
            return start...end
        } else {
            return nil
        }
    }
    
    func firstEntryDate() throws -> Date? {
        let entries = try self.getEntries()
        var firstEntry: OSLogEntry?
        for entry in entries {
            if firstEntry == nil {
                firstEntry = entry
                break
            }
        }
        return firstEntry?.date
    }
    
    func lastEntryDate() throws -> Date? {
        let position = self.position(timeIntervalSinceEnd: -0.1)
        let lastEntries = try self.getEntries(at: position)
        
        // Can't just do `lastEntries.last` apparently.
        var lastEntry: OSLogEntry?
        for entry in lastEntries {
            lastEntry = entry
        }
        return lastEntry?.date
    }
}

extension OTSystemLogType {
    var level: OSLogEntryLog.Level {
        switch self {
        case .debug: .debug
        case .info: .info
        case .default: .notice
        case .error: .error
        case .fault: .fault
        @unknown default: .undefined
        }
    }
}

extension UTType {
    static let logarchive = UTType("com.apple.logarchive")!
}

extension String {
    static let otterPathExtension = "otter"
}

// MARK: - OSAllocatedUnfairLock

extension OSAllocatedUnfairLock {
    
    var currentState: State { self.withLock { $0 } }
}

// MARK: - String

extension String {
    
    /// Converts this string from whatever it is currently to a real bonafide Swift `String`.
    ///
    /// When we get a String from the parser, we might get something funky.
    /// It might be something like an `NSPathStore2` or some weird thing under the hood.
    /// This causes a bunch of other things to be slow, so converting it to a real `String` helps.
    var stringocchioWantsToBeARealBoy: String {
        var maybeNonContiguous = self
        maybeNonContiguous.makeContiguousUTF8()
        return maybeNonContiguous
    }
}
