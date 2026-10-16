//
//  WorkoutDataTypes.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
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

extension Workout {
    nonisolated enum Kind: String, CaseIterable {
        case badminton, baseball, golf, pickleball, racquetball,
             softball, squash, tableTennis, tennis, other

        var name: String {
            switch self {
            case .badminton: "Badminton"
            case .baseball: "Baseball"
            case .golf: "Golf"
            case .pickleball: "Pickleball"
            case .racquetball: "Racquetball"
            case .softball: "Softball"
            case .squash: "Squash"
            case .tableTennis: "Table Tennis"
            case .tennis: "Tennis"
            case .other: "Other"
            }
        }

        var symbol: String {
            switch self {
            case .badminton: "figure.badminton"
            case .baseball: "figure.baseball"
            case .golf: "figure.golf"
            case .pickleball: "figure.pickleball"
            case .racquetball: "figure.racquetball"
            case .softball: "figure.softball"
            case .squash: "figure.squash"
            case .tableTennis: "figure.table.tennis"
            case .tennis: "figure.tennis"
            case .other: "figure.mixed.cardio"
            }
        }

        var activityType: HKWorkoutActivityType {
            switch self {
            case .badminton: .badminton
            case .baseball: .baseball
            case .golf: .golf
            case .pickleball: .pickleball
            case .racquetball: .racquetball
            case .softball: .softball
            case .squash: .squash
            case .tableTennis: .tableTennis
            case .tennis: .tennis
            case .other: .other
            }
        }
    }
}
