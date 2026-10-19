//
//  WorkoutControlsView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import SwiftUI
import WatchKit
import HealthKit

struct WorkoutControlsView: View {
    var store: Workout.Store

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                ControlButton(title: "End", symbol: "xmark", color: .red) {
                    store.end()
                }
                ControlButton(
                    title:  store.showPausedButton ? "Resume" : "Pause",
                    symbol: store.showPausedButton ? "play.fill" : "pause.fill",
                    color: .yellow
                ) {
                    store.togglePause()
                }
            }
            GridRow {
                ControlButton(title: "Water Lock", symbol: "drop.fill", color: .cyan) {
                    WKInterfaceDevice.current().enableWaterLock()
                }
                ControlButton(
                    title: store.sessionType.wildcardTitle,
                    symbol: store.sessionType.wildcardSymbol,
                    color: .purple
                ) {
                    store.wildcardTapped()
                }
            }
        }
        .sensoryFeedback(.success, trigger: store.markCount)
    }
}

/// Round tinted button with a label underneath, like the built-in Workout controls.
struct ControlButton: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .background(color.opacity(0.28), in: Circle())
            .frame(width: 64, height: 64)

            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

#Preview {
    let session = try! HKWorkoutSession(healthStore: HKHealthStore(), configuration: HKWorkoutConfiguration())
    WorkoutControlsView(store: Workout.Store(workout: session, kind: .tennis, sessionType: .live, sensor: Motion.Sensor(deliveringOn: Motion.queue)))
}
