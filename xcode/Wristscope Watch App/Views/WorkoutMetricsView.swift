//
//  WorkoutMetricsView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import SwiftUI
import HealthKit

struct WorkoutMetricsView: View {
    var store: Workout.Store

    /// Ring is full at this heart rate. Placeholder until real zones exist.
    private let maxHeartRate = 200.0

    var body: some View {
        VStack(spacing: 8) {
            heartRateRing

            HStack(spacing: 14) {
                secondary(energyText, unit: "KCAL", color: .orange)
                secondary(distanceText, unit: distanceUnit, color: .green)
                secondary(stepsText, unit: "STEPS", color: .cyan)
            }

            duration
        }
    }

    // MARK: - Pieces

    private var heartRateRing: some View {
        ZStack {
            Circle().stroke(.gray.opacity(0.3), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min((store.heartRate ?? 0) / maxHeartRate, 1))
                .stroke(.red, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: store.heartRate)

            VStack(spacing: 0) {
                Text(store.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
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

    private func secondary(_ value: String, unit: String, color: Color) -> some View {
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

    /// The builder tracks elapsed time (paused time excluded); we just redraw once a second.
    private var duration: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = store.session.associatedWorkoutBuilder().elapsedTime(at: context.date)
            Text(Self.format(elapsed))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.yellow)
        }
    }

    // MARK: - Formatting

    private var usesMetric: Bool { Locale.current.measurementSystem == .metric }

    private var energyText: String { "\(Int(store.activeEnergy.rounded()))" }

    private var stepsText: String {
        store.steps.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    private var distanceText: String {
        let meters = store.distance
        let value = usesMetric ? meters / 1000 : meters / 1609.344
        return value.formatted(.number.precision(.fractionLength(2)))
    }

    private var distanceUnit: String { usesMetric ? "KM" : "MI" }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    let session = try! HKWorkoutSession(healthStore: HKHealthStore(), configuration: HKWorkoutConfiguration())
    WorkoutMetricsView(store: Workout.Store(session: session, type: .live))
}
