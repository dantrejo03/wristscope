//
//  WorkoutMetricsView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import SwiftUI
import HealthKit

struct WorkoutMetricsView: View {
    typealias Formatter = Workout.Metrics.Formatter
    
    let store: Workout.Metrics.Store

    var body: some View {
        VStack(spacing: 8) {
            HeartRateRing(
                rate: store.heartRate,
                maxRate: store.maxHeartRate
            )

            HStack(spacing: 14) {
                SecondaryStat(
                    value: Formatter.energy(from: store.activeEnergy),
                    unit: "KCAL",
                    color: .orange
                )
                
                SecondaryStat(
                    value: Formatter.distance(from: store.distance, usesMetric),
                    unit: distanceUnit,
                    color: .green
                )
                
                SecondaryStat(
                    value: Formatter.steps(from: store.steps),
                    unit: "STEPS",
                    color: .cyan
                )
            }

            DurationView(elapsed: { store.elapsedTime(at: $0) })
        }
    }

    private var usesMetric: Bool { Locale.current.measurementSystem == .metric }

    private var distanceUnit: String { usesMetric ? "KM" : "MI" }
}

#Preview {
    let session = try! HKWorkoutSession(healthStore: HKHealthStore(), configuration: HKWorkoutConfiguration())
    WorkoutMetricsView(store: Workout.Metrics.Store(workout: session))
}


private struct HeartRateRing: View {
    typealias Formatter = Workout.Metrics.Formatter
    
    let rate: Double?
    let maxRate: Double
    
    var body: some View {
        ZStack {
            Circle().stroke(.gray.opacity(0.3), lineWidth: 7)
            Circle()
                .trim(
                    from: 0,
                    to: Formatter.intensity(for: rate, max: maxRate)
                )
                .stroke(.red, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: rate)

            VStack(spacing: 0) {
                Text(Formatter.string(from: rate))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .contentTransition(.numericText())
                Text("BPM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 118, height: 118)
    }
}

#Preview("Heart rate ring") {
    HeartRateRing(rate: 60, maxRate: 200)
}


private struct SecondaryStat: View {
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DurationView: View {
    typealias Formatter = Workout.Metrics.Formatter
    let elapsed: (Date) -> TimeInterval
    
    init(elapsed: @escaping (Date) -> TimeInterval) {
        self.elapsed = elapsed
    }
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Formatter.elapsedTime(from: elapsed(context.date)))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.yellow)
        }
    }
}
