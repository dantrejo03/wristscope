//
//  ActiveWorkoutView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI
import WatchKit

struct ActiveWorkoutView: View {
    
    @State private var tabSelection: Workout.Store.Tab = .controls
    
    var body: some View {
        TabView(selection: $tabSelection) {
            WorkoutMetricsView().tag(Workout.Store.Tab.metrics)
            WorkoutControlsView().tag(Workout.Store.Tab.controls)
            NowPlayingView().tag(Workout.Store.Tab.nowPlaying)
        }
    }
}

struct WorkoutControlsView: View {
    var body: some View {
        Text("Controls")
    }
}

struct WorkoutMetricsView: View {
    var body: some View {
        Text("Metrics")
    }
}


#Preview {
    ActiveWorkoutView()
}
