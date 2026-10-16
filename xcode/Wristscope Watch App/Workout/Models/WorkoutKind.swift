//
//  WorkoutKind.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import Foundation
import HealthKit


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

extension Workout.Kind: UserDefaultsBacked {
    static let key: String = "lastWorkoutKind"
}
