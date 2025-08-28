//
//  AsyncCoalescer.swift
//  Otter
//
//  Created by Tim Mahoney on 2/8/24.
//

import Foundation

public actor Coalescer {
    
    var coalescedStart = Date.distantFuture
    var task: Task<Void, Error>?
    var currentTaskID: UUID?
    var isRunning = false
    
    public nonisolated func coalesce(delay: TimeInterval, cancelPrevious: Bool = true, block: @Sendable @escaping () async throws -> ()) {
        Task {
            try await self._coalesce(delay: delay, cancelPrevious: cancelPrevious, block: block)
        }
    }
    
    private func _coalesce(delay: TimeInterval, cancelPrevious: Bool = true, block: @Sendable @escaping () async throws -> ()) throws {
        let previousTask = self.task
        
        if cancelPrevious {
            var shouldCancelPrevious = false
            if self.isRunning {
                shouldCancelPrevious = true
            } else {
                let newStart = Date.now + delay
                if self.coalescedStart > newStart {
                    shouldCancelPrevious = true
                }
            }
            
            if shouldCancelPrevious {
                previousTask?.cancel()
            }
        }
        let taskID = UUID()
        self.currentTaskID = taskID
        self.task = Task.detached {
            try? await previousTask?.value
            try await self.run(taskID: taskID, delay: delay, block: block)
        }
    }
    
    private func run(taskID: UUID, delay: TimeInterval, block: @Sendable @escaping () async throws -> ()) async throws {
        self.isRunning = true
        self.coalescedStart = .distantFuture
        try await Task.sleep(for: .seconds(delay))
        try await block()
        if taskID == self.currentTaskID {
            self.task = nil
            self.currentTaskID = nil
        }
        self.isRunning = false
    }
}
