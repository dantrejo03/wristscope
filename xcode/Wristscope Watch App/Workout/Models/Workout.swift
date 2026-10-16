//
//  Workout.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import Foundation
import HealthKit


enum Workout {}

nonisolated enum WorkoutError: Error {
    case healthDataUnavailable
}

extension Workout {
    nonisolated enum Event: Sendable {
        case prepared
        case running
        case paused
        case ended(Date)
        case failed(any Error)
    }
}

extension Workout {
    /// One live reading from the workout builder.
    nonisolated enum Metric: Sendable {
        case heartRate(Double)      // beats per minute
        case activeEnergy(Double)   // kilocalories so far
        case distance(Double)       // meters so far
        case steps(Double)          // steps so far

        init?(_ statistics: HKStatistics) {
            switch statistics.quantityType {
            case HKQuantityType(.heartRate):
                guard let quantity = statistics.mostRecentQuantity() else { return nil }
                self = .heartRate(quantity.doubleValue(for: .count().unitDivided(by: .minute())))
            case HKQuantityType(.activeEnergyBurned):
                guard let quantity = statistics.sumQuantity() else { return nil }
                self = .activeEnergy(quantity.doubleValue(for: .kilocalorie()))
            case HKQuantityType(.distanceWalkingRunning):
                guard let quantity = statistics.sumQuantity() else { return nil }
                self = .distance(quantity.doubleValue(for: .meter()))
            case HKQuantityType(.stepCount):
                guard let quantity = statistics.sumQuantity() else { return nil }
                self = .steps(quantity.doubleValue(for: .count()))
            default:
                return nil
            }
        }
    }
}
