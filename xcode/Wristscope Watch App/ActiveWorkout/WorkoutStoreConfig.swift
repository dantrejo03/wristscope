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
    }
}


extension Workout.Store.Config {
    /// Reads the session type, sample rate and reference frame saved in settings.
    init(
        workout: HKWorkoutSession,
        kind: Workout.Kind,
        sensor: Motion.Sensor,
        connectivity: WatchConnectivityManager
    ) {
        self.init(
            workout: workout,
            kind: kind,
            sensor: sensor,
            connectivity: connectivity,
            sessionType: .current,
            sampleRate: .current,
            referenceFrame: .currentAvailable
        )
    }

    /// Seconds between flushes. Live sends each flush to the phone, so this is about how far
    /// behind the phone runs.
    var flushInterval: TimeInterval {
        switch sessionType {
        // Rep and workout sessions use the live sink until they have their own.
        case .live, .rep, .workout: 0.1
        }
    }

    /// Bytes for one flush interval of all three sensors at the sample rate, doubled so a
    /// late flush doesn't drop samples.
    var capacity: Int {
        // The 1 is each record's tag.
        let bytesPerRound = Motion.SampleTag.allCases.reduce(0) {
            $0 + 1 + Motion.SampleFormatter.byteSize(from: $1)
        }
        let bytesPerFlush = Double(bytesPerRound * sampleRate.hertz) * flushInterval
        return Int((2 * bytesPerFlush).rounded(.up))
    }
}
