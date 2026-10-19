//
//  MotionActor.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/17/26.
//

import Foundation

enum Motion {
    
    nonisolated static let queue = DispatchSerialQueue(
        label: "com.wristscope.motion", qos: .userInitiated
    )
    
    /// Code marked `@Motion.Actor` runs on `Motion.queue`.
    @globalActor
    actor Actor {
        static let shared = Actor()
        nonisolated var unownedExecutor: UnownedSerialExecutor {
            Motion.queue.asUnownedSerialExecutor()
        }

        /// For CoreMotion handlers, which run on `Motion.queue` but outside Swift concurrency.
        /// Traps if called from anywhere else. Same approach as `MainActor.assumeIsolated`.
        static func assumeIsolated<T: Sendable>(_ operation: @Motion.Actor () throws -> T) rethrows -> T {
            shared.preconditionIsolated()
            return try withoutActuallyEscaping(operation) { fn in
                try unsafeBitCast(fn, to: (() throws -> T).self)()
            }
        }
    }
}
