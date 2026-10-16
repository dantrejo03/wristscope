//
//  WorkoutManager.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation
import HealthKit
import os


extension Workout {
    final class Manager {
        static let shared = Workout.Manager()
        
        private let healthStore = HKHealthStore()
        
        private init() {}
        
        var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
        
        func needsAuthorization() async throws -> Bool {
            guard isAvailable else { throw WorkoutError.healthDataUnavailable }
            let status = try await healthStore.statusForAuthorizationRequest(
                toShare: Self.shareTypes,
                read: Self.readTypes
            )
            return status == .shouldRequest
        }
        
        func requestAuthorization() async throws {
            guard isAvailable else { throw WorkoutError.healthDataUnavailable }
            try await healthStore.requestAuthorization(
                toShare: Self.shareTypes,
                read: Self.readTypes
            )
        }
        
        /// Creates the session and warms up the sensors while the countdown runs. Nothing is
        /// recorded yet. `delegate` hears `.prepared` once the session is ready for `begin`.
        func prepare(
            _ activity: HKWorkoutActivityType,
            delegate: any HKWorkoutSessionDelegate
        ) throws -> HKWorkoutSession {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activity

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            // Set before `prepare()`, so the change to `.prepared` can't be missed
            session.delegate = delegate
            session.prepare()
            return session
        }

        /// Starts the workout clock and Health data collection at the same moment.
        func begin(_ session: HKWorkoutSession) async throws {
            let builder = session.associatedWorkoutBuilder()

            let startDate = Date()
            session.startActivity(with: startDate)
            do {
                try await builder.beginCollection(at: startDate)
            } catch {
                session.end()
                builder.discardWorkout()
                throw error
            }
        }
    }
}


// MARK: - Constants

extension Workout.Manager {
    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.stepCount),
    ]

    private static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.stepCount),
    ]
}



//extension Workout {
//    /// The workout only exists to keep the app running while streaming, so the only Health
//    /// data it asks for is permission to save the workout itself.
//    final class Manager {
//
//        static let shared = Workout.Manager()
//
//        private let healthStore = HKHealthStore()
//
//        private init() {}
//
//        var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
//
//        var canRecordWorkouts: Bool {
//            healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
//        }
//
//        func requestAuthorization() async throws {
//            guard isAvailable else { throw WorkoutError.healthDataUnavailable }
//            try await healthStore.requestAuthorization(
//                toShare: Self.shareTypes,
//                read: Self.readTypes
//            )
//        }
//
//        func recover() async -> HKWorkoutSession? {
//            guard isAvailable else { return nil }
//
//            do {
//                return try await healthStore.recoverActiveWorkoutSession()
//            } catch {
//                return nil
//            }
//        }
//
//        /// Workouts aren't recovered, so one left running by an earlier launch is ended without saving.
//        func discardLeftoverSession() async {
//            guard let session = await recover() else { return }
//
//            AppLog.workout.notice("Discarding a workout left over from an earlier launch.")
//            discardWorkout(session)
//        }
//
//        func startWorkout(delegate: any HKWorkoutSessionDelegate) async throws -> HKWorkoutSession {
//            let configuration = HKWorkoutConfiguration()
//            configuration.activityType = .other
//            configuration.locationType = .unknown
//
//            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
//            let builder = session.associatedWorkoutBuilder()
//            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
//            session.delegate = delegate
//
//            let startDate = Date()
//            session.startActivity(with: startDate)
//            do {
//                try await builder.beginCollection(at: startDate)
//            } catch {
//                discardWorkout(session)
//                throw error
//            }
//
//            return session
//        }
//
//        /// Saves the workout to Health. Call once the session has reached `.ended`.
//        func finishWorkout(_ session: HKWorkoutSession, at endDate: Date) async throws {
//            let builder = session.associatedWorkoutBuilder()
//            try await builder.endCollection(at: endDate)
//            _ = try await builder.finishWorkout()
//        }
//
//        func discardWorkout(_ session: HKWorkoutSession) {
//            session.end()
//            session.associatedWorkoutBuilder().discardWorkout()
//        }
//    }
//}
//
//extension Workout.Manager {
//    private static let shareTypes: Set<HKSampleType> = [
//        HKObjectType.workoutType(),
//    ]
//
//    private static let readTypes: Set<HKObjectType> = []
//}
//
//
//// MARK: - Observer
//
//extension Workout {
//    nonisolated final class Observer: NSObject, HKWorkoutSessionDelegate {
//        let events: AsyncStream<Event>
//        private let continuation: AsyncStream<Event>.Continuation
//
//        override init() {
//            let (events, continuation) = AsyncStream<Event>.makeStream(
//                bufferingPolicy: .bufferingNewest(8)
//            )
//            self.events = events
//            self.continuation = continuation
//            super.init()
//        }
//
//        deinit { continuation.finish() }
//
//        func workoutSession(
//            _ workoutSession: HKWorkoutSession,
//            didChangeTo toState: HKWorkoutSessionState,
//            from fromState: HKWorkoutSessionState,
//            date: Date
//        ) {
//            guard toState == .ended else { return }
//            continuation.yield(.ended(date))
//        }
//
//        func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
//            continuation.yield(.failed(error))
//        }
//    }
//}
