//
//  ActiveWorkoutView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI
import WatchKit
import HealthKit

struct ActiveWorkoutView: View {
    @State var store: Workout.Store

    var body: some View {
        TabView(selection: $store.tabSelection) {
            WorkoutMetricsView(store: store).tag(Workout.Store.Tab.metrics)
            WorkoutControlsView(store: store).tag(Workout.Store.Tab.controls)
            NowPlayingView().tag(Workout.Store.Tab.nowPlaying)
        }
    }
}

#Preview {
    let session = try! HKWorkoutSession(healthStore: HKHealthStore(), configuration: HKWorkoutConfiguration())
    ActiveWorkoutView(store: Workout.Store(session: session, type: .live))
}
