//
//  AsyncLock.swift
//  Otter
//
//  Created by Tim Mahoney on 2/23/24.
//

import Foundation

/// A lock that works in an async context.
/// Thanks, ChatGPT!
actor AsyncLock {
    
    private var isLocked: Bool = false
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []
    
    func acquire() async {
        if self.isLocked {
            await withCheckedContinuation { continuation in
                self.waitingContinuations.append(continuation)
            }
        } else {
            self.isLocked = true
        }
    }
    
    func release() {
        if let nextContinuation = self.waitingContinuations.popLast() {
            nextContinuation.resume()
        } else {
            self.isLocked = false
        }
    }
    
    func withLock<T>(body: () async throws -> T) async rethrows -> T {
        await self.acquire()
        defer {
            self.release()
        }
        return try await body()
    }
}
