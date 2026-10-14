//
//  WorkoutDataTypes.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation


enum Workout {}

nonisolated enum WorkoutError: Error {
    case healthDataUnavailable
}

extension Workout {
    nonisolated enum Event: Sendable {
        case ended(Date)
        case failed(any Error)
    }
}
