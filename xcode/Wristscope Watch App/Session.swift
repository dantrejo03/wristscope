//
//  Session.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation
import HealthKit
import os


enum SessionStartFailure: Error {
    case healthDenied
    case couldNotStart
}


/// Everything a session needs is running for as long as this exists.
final class Session {

    struct Ending {
        let date: Date
        let wasRequested: Bool
    }

    /// The motion sources that started. A source is left out when this device doesn't have it.
    let activeSources: Set<Motion.Source>

    private let motion: Motion.Controller
    private let workout: Workout.Manager
    private let workoutSession: HKWorkoutSession

    // `HKWorkoutSession.delegate` is weak, so this is the only strong reference.
    private let observer: Workout.Observer

    private var isEndRequested = false

    private init(
        activeSources: Set<Motion.Source>,
        motion: Motion.Controller,
        workout: Workout.Manager,
        workoutSession: HKWorkoutSession,
        observer: Workout.Observer
    ) {
        self.activeSources = activeSources
        self.motion = motion
        self.workout = workout
        self.workoutSession = workoutSession
        self.observer = observer
    }

    static func start(
        motion: Motion.Controller,
        workout: Workout.Manager
    ) async throws(SessionStartFailure) -> Session {
        // Permission first, so a "no" leaves nothing running to undo.
        do {
            try await workout.requestAuthorization()
        } catch {
            AppLog.workout.error("Requesting Health authorization failed: \(error.localizedDescription)")
            throw .couldNotStart
        }

        guard workout.canRecordWorkouts else {
            throw .healthDenied
        }

        // The workout goes first because it keeps the app running when the wrist drops.
        let observer = Workout.Observer()
        let workoutSession: HKWorkoutSession
        do {
            workoutSession = try await workout.startWorkout(delegate: observer)
        } catch {
            AppLog.workout.error("Starting the workout failed: \(error.localizedDescription)")
            throw .couldNotStart
        }

        let activeSources = motion.startSensors()

        return Session(
            activeSources: activeSources,
            motion: motion,
            workout: workout,
            workoutSession: workoutSession,
            observer: observer
        )
    }

    /// Asks the workout to end. `ended()` returns once it has.
    func end() {
        isEndRequested = true
        workoutSession.end()
    }

    /// Waits for the workout to end, whether `end()` asked for it or the system ended it,
    /// then stops the sensors.
    func ended() async -> Ending {
        let date = await workoutEndDate()

        motion.stopSensors()

        return Ending(date: date, wasRequested: isEndRequested)
    }

    /// Saves the workout to Health. Call once `ended()` has returned.
    func saveWorkout(endingAt date: Date) async {
        do {
            try await workout.finishWorkout(workoutSession, at: date)
        } catch {
            AppLog.workout.error("Saving the workout failed: \(error.localizedDescription)")
        }
    }

    /// Throws the workout away without saving it. Call once `ended()` has returned.
    func discardWorkout() {
        workout.discardWorkout(workoutSession)
    }

    private func workoutEndDate() async -> Date {
        for await event in observer.events {
            switch event {
            case .ended(let date):
                return date
            case .failed(let error):
                AppLog.workout.error("The workout session failed: \(error.localizedDescription)")
                workoutSession.end()
                return Date()
            }
        }

        // The stream only finishes when the observer is released, and this session holds it.
        return Date()
    }
}
