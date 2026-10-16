//
//  WorkoutMetricsFormatter.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import Foundation


extension Workout.Metrics {
    nonisolated final class Formatter {
        
        static func string(from heartRate: Double?) -> String {
            guard let heartRate else { return "--" }
            return "\(Int(heartRate.rounded()))"
        }
        
        static func intensity(for heartRate: Double?, max maxHeartRate: Double) -> Double {
            guard let heartRate, maxHeartRate > 0 else { return 0 }
            return min(heartRate / maxHeartRate, 1.0)
        }
        
        static func elapsedTime(from interval: TimeInterval) -> String {
            let total = Int(interval)
            let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
            return h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%02d:%02d", m, s)
        }
        
        static func energy(from value: Double) -> String { "\(Int(value.rounded()))" }
        
        static func steps(from value: Double) -> String {
            value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        }
        
        static func distance(from value: Double, _ usesMetric: Bool) -> String {
            let meters = value
            let value = usesMetric ? meters / 1000 : meters / 1609.344
            return value.formatted(.number.precision(.fractionLength(2)))
        }
        
        
    }
}
