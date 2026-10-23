//
//  WorkoutStoreConfig.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/19/26.
//

import Foundation
import HealthKit


extension Workout.Store {
    /// Everything a workout store is built from. The init that reads settings is in an
    /// extension so the memberwise init stays, for previews and tests.
    struct Config {
        let workout: HKWorkoutSession
        let kind: Workout.Kind
        let sensor: Motion.Sensor
        let connectivity: WatchConnectivityManager
        let sessionType: SessionType
        let sampleRate: SampleRate
        let referenceFrame: ReferenceFrame
        /// Logs every live message for the connectivity benchmark. Only debug builds turn it on.
        let isBenchmarking: Bool
    }
}


extension Workout.Store.Config {
    /// Reads the session type, sample rate and reference frame saved in settings, and in debug
    /// builds whether to benchmark.
    init(
        workout: HKWorkoutSession,
        kind: Workout.Kind,
        sensor: Motion.Sensor,
        connectivity: WatchConnectivityManager
    ) {
        #if DEBUG
        let isBenchmarking = BenchmarkSetting.isOn
        #else
        let isBenchmarking = false
        #endif

        self.init(
            workout: workout,
            kind: kind,
            sensor: sensor,
            connectivity: connectivity,
            sessionType: .current,
            sampleRate: .current,
            referenceFrame: .currentAvailable,
            isBenchmarking: isBenchmarking
        )
    }

    /// Seconds between flushes. Live sends each flush to the phone, so this is about how far
    /// behind the phone runs.
    var flushInterval: TimeInterval {
        switch sessionType {
        // Rep and workout sessions use the live sink until they have their own.
        case .live, .rep, .workout: 1
        }
    }

    /// Bytes for two seconds of all three sensors at the sample rate, or two flush intervals if
    /// that's longer. It's sized by time because watchOS sometimes pauses the app, and when it
    /// resumes every reading it missed arrives at once: the benchmark saw a 1.1 s pause, which
    /// overflowed a buffer of two 50 ms flushes. Not much bigger, because a full buffer goes out
    /// as one message and WatchConnectivity refuses messages that are too large.
    var capacity: Int {
        let bytesPerSecond = Motion.SampleFormatter.bytesPerRound * sampleRate.hertz
        let seconds = max(2, 2 * flushInterval)
        return Int((Double(bytesPerSecond) * seconds).rounded(.up))
    }
}
