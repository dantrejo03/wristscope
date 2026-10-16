//
//  WorkoutSummaryView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import SwiftUI


struct WorkoutSummaryView: View {
    typealias Formatter = Workout.Metrics.Formatter

    let summary: Workout.Summary
    let store: ApplicationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label(summary.kind.name, systemImage: summary.kind.symbol)
                    .font(.headline)
                    .foregroundStyle(.green)

                Text(summary.startDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text("TIME")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(Formatter.elapsedTime(from: summary.duration))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.yellow)
                }

                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        StatCell(
                            value: Formatter.energy(from: summary.activeEnergy),
                            unit: "KCAL",
                            color: .orange
                        )
                        StatCell(
                            value: Formatter.string(from: summary.averageHeartRate),
                            unit: "AVG BPM",
                            color: .red
                        )
                    }
                    GridRow {
                        StatCell(
                            value: Formatter.distance(from: summary.distance, usesMetric),
                            unit: usesMetric ? "KM" : "MI",
                            color: .green
                        )
                        StatCell(
                            value: Formatter.steps(from: summary.steps),
                            unit: "STEPS",
                            color: .cyan
                        )
                    }
                }
                
                Button {
                    store.dismissSummary()
                } label: {
                    Text("Done")
                }
                .tint(.blue)
        
            }
        }
    }

    private var usesMetric: Bool { Locale.current.measurementSystem == .metric }
}

private struct StatCell: View {
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    WorkoutSummaryView(
        summary: Workout.Summary(
            kind: .tennis,
            startDate: .now.addingTimeInterval(-2538),
            duration: 2538,
            activeEnergy: 312,
            distance: 3862,
            steps: 4100,
            averageHeartRate: 138
        ),
        store: ApplicationStore()
    )
}
