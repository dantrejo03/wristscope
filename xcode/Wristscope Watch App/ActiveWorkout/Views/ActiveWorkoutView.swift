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
        switch store.state {
        case .running, .paused:
            TabView(selection: $store.tabSelection) {
                WorkoutControlsView(store: store).tag(Workout.Store.Tab.controls)
                WorkoutMetricsView(store: store.metricsStore).tag(Workout.Store.Tab.metrics)
                NowPlayingView().tag(Workout.Store.Tab.nowPlaying)
            }
        case .recordingRep(let since):
            RepRecordingView(since: since, onStop: store.toggleRep)
        case .displayingPhoneConnection:
            PhoneConnectionView(onDone: store.hidePhoneConnectionStatus)
        case .ending:
            ProgressView("Saving…")
        }
    }
}

#Preview {
    let session = try! HKWorkoutSession(healthStore: HKHealthStore(), configuration: HKWorkoutConfiguration())
    ActiveWorkoutView(store: Workout.Store(workout: session, kind: .tennis, sessionType: .rep))
}
