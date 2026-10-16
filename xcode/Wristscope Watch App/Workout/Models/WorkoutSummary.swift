//
//  WorkoutSummary.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import Foundation
import HealthKit


extension Workout {
    /// Final numbers for a finished workout. A plain value, so the summary screen never
    /// needs HealthKit or the workout store.
    nonisolated struct Summary: Sendable {
        let kind: Kind
        let startDate: Date
        /// Time spent running. Paused time is left out.
        let duration: TimeInterval
        /// Kilocalories.
        let activeEnergy: Double
        /// Meters.
        let distance: Double
        let steps: Double
        /// Beats per minute. Nil if no heart rate was collected.
        let averageHeartRate: Double?
    }
}

extension Workout.Summary {
    /// Reads the final numbers from a builder whose collection has ended.
    init(kind: Workout.Kind, builder: HKWorkoutBuilder) {
        func total(_ identifier: HKQuantityTypeIdentifier, in unit: HKUnit) -> Double {
            builder.statistics(for: HKQuantityType(identifier))?.sumQuantity()?.doubleValue(for: unit) ?? 0
        }

        self.init(
            kind: kind,
            startDate: builder.startDate ?? .now,
            duration: builder.elapsedTime(at: builder.endDate ?? .now),
            activeEnergy: total(.activeEnergyBurned, in: .kilocalorie()),
            distance: total(.distanceWalkingRunning, in: .meter()),
            steps: total(.stepCount, in: .count()),
            averageHeartRate: builder.statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?
                .doubleValue(for: .count().unitDivided(by: .minute()))
        )
    }
}
