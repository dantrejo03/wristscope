//
//  WorkoutObservers.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import Foundation
import HealthKit


extension Workout {
    enum Session {}
}

extension Workout.Session {
    /// HealthKit calls the delegate on a background queue, so this forwards each change
    /// as an `Event` for the main actor to handle in order.
    nonisolated final class Observer: NSObject, HKWorkoutSessionDelegate {
        let events: AsyncStream<Workout.Event>
        private let continuation: AsyncStream<Workout.Event>.Continuation

        override init() {
            let (events, continuation) = AsyncStream<Workout.Event>.makeStream(
                bufferingPolicy: .bufferingNewest(8)
            )
            self.events = events
            self.continuation = continuation
            super.init()
        }

        deinit { continuation.finish() }

        func workoutSession(
            _ workoutSession: HKWorkoutSession,
            didChangeTo toState: HKWorkoutSessionState,
            from fromState: HKWorkoutSessionState,
            date: Date
        ) {
            switch toState {
            case .prepared: continuation.yield(.prepared)
            case .running: continuation.yield(.running)
            case .paused: continuation.yield(.paused)
            case .ended: continuation.yield(.ended(date))
            default: break
            }
        }

        func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
            continuation.yield(.failed(error))
        }
    }
}

extension Workout {
    nonisolated enum Builder {}
}

extension Workout.Builder {
    /// HealthKit calls the builder delegate on a background queue, so this reads each
    /// update into a `Metric` for the main actor to handle in order.
    nonisolated final class Observer: NSObject, HKLiveWorkoutBuilderDelegate {
        let metrics: AsyncStream<Workout.Metric>
        private let continuation: AsyncStream<Workout.Metric>.Continuation

        override init() {
            let (metrics, continuation) = AsyncStream<Workout.Metric>.makeStream(
                bufferingPolicy: .bufferingNewest(8)
            )
            self.metrics = metrics
            self.continuation = continuation
            super.init()
        }

        deinit { continuation.finish() }

        func workoutBuilder(
            _ workoutBuilder: HKLiveWorkoutBuilder,
            didCollectDataOf collectedTypes: Set<HKSampleType>
        ) {
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType,
                      let statistics = workoutBuilder.statistics(for: quantityType),
                      let metric = Workout.Metric(statistics)
                else { continue }
                continuation.yield(metric)
            }
        }

        // Pause and resume also arrive as session state changes, which is where they'll be tracked
        func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    }
}
