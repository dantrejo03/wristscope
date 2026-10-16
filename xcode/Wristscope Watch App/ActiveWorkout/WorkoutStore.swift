//
//  WorkoutStore.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import Foundation
import HealthKit


extension Workout {
    @Observable
    final class Store {
        // MARK: Health
        @ObservationIgnored let workout: HKWorkoutSession
        @ObservationIgnored let kind: Workout.Kind
        @ObservationIgnored let sessionType: SessionType
        @ObservationIgnored let metricsStore: Workout.Metrics.Store
        @ObservationIgnored private let builderObserver = Builder.Observer()
        @ObservationIgnored private var observationTask: Task<Void, Never>?
        
        // MARK: State
        
        // First tab that gets shown
        var tabSelection: Tab = .metrics
        
        private(set) var state: State = .running
        
        var showPausedButton: Bool {
            if case .paused = state { return true }
            else { return false }
        }

        /// Goes up once each marker is saved, so the view can confirm it with a tap on the wrist.
        private(set) var markCount = 0

        /// Read once collection ends. The application store shows it when the session ends.
        @ObservationIgnored private(set) var summary: Workout.Summary?

        /// Set by End, so a workout the user finished can be told apart from one that ended
        /// some other way.
        @ObservationIgnored private(set) var isEndRequested = false

        @ObservationIgnored private var finishTask: Task<Void, Never>?

        /// Running or paused, read straight from the session. Used when leaving a screen that
        /// covers the controls, since pause events don't change `state` while one is up.
        private var sessionState: State {
            workout.state == .paused ? .paused : .running
        }


        init(workout: HKWorkoutSession, kind: Workout.Kind, sessionType: SessionType) {
            self.workout = workout
            self.kind = kind
            self.sessionType = sessionType
            self.metricsStore = Metrics.Store(workout: workout)
            
            // Set before `beginCollection`, so no readings are missed
            workout.associatedWorkoutBuilder().delegate = builderObserver
            
            setUpObservationTask()
        }

        deinit {
            observationTask?.cancel()
        }

        /// Only asks HealthKit. The button flips once the session reports the change.
        func togglePause() {
            if case .paused = state {
                workout.resume()
            } else {
                workout.pause()
            }
        }

        func end() {
            isEndRequested = true
            state = .ending
            workout.stopActivity(with: .now)
        }

        /// Saves whatever was collected, then ends the session. Several events can lead here,
        /// so the first call starts the save and the rest wait for that same one. The summary
        /// is read before saving, so it's there even if saving fails.
        func finish(at endDate: Date) async {
            if finishTask == nil {
                state = .ending
                finishTask = Task {
                    let builder = workout.associatedWorkoutBuilder()
                    do {
                        try await builder.endCollection(at: endDate)
                        summary = Workout.Summary(kind: kind, builder: builder)
                        _ = try await builder.finishWorkout()
                    } catch {

                    }
                    workout.end()
                }
            }
            await finishTask?.value
        }

        /// Throws everything away, for a session that ends before the workout began.
        func discard() {
            workout.end()
            workout.associatedWorkoutBuilder().discardWorkout()
        }

        /// The wildcard button's action, which depends on the session type saved in settings.
        func wildcardTapped() {
            switch sessionType {
            case .workout:
                markTime()
            case .rep:
                toggleRep()
            case .live:
                showPhoneConnectionStatus()
            }
        }
        
        private func showPhoneConnectionStatus() {
            switch state {
            case .running, .paused: state = .displayingPhoneConnection
            case .displayingPhoneConnection, .recordingRep, .ending: break
            }
        }

        func hidePhoneConnectionStatus() {
            guard case .displayingPhoneConnection = state else { return }
            state = sessionState
        }

        /// Starts a rep from the controls, or stops the one recording. Pause stops the motion
        /// sensors, so a rep can only start while running.
        func toggleRep() {
            switch state {
            case .running: state = .recordingRep(since: .now)
            case .recordingRep: state = sessionState
            case .paused, .displayingPhoneConnection, .ending: break
            }
        }

        private func markTime() {
            let marker = HKWorkoutEvent(
                type: .marker,
                dateInterval: DateInterval(start: .now, duration: 0),
                metadata: nil
            )
            Task {
                do {
                    try await workout.associatedWorkoutBuilder().addWorkoutEvents([marker])
                    markCount += 1
                } catch {

                }
            }
        }
    }
}

extension Workout.Store {
    enum Tab {
        case metrics, controls, nowPlaying
    }
    
    enum State {
        case running
        case paused
        case displayingPhoneConnection
        case recordingRep(since: Date)
        case ending
    }
}


// MARK: - Observation

extension Workout.Store {
    private func setUpObservationTask() {
        let metrics = builderObserver.metrics
        observationTask = Task { [weak self] in
            for await metric in metrics {
                self?.handle(metric)
            }
        }
    }

    private func handle(_ metric: Workout.Metric) {
        switch metric {
        case .heartRate(let value): metricsStore.heartRate = value
        case .activeEnergy(let value): metricsStore.activeEnergy = value
        case .distance(let value): metricsStore.distance = value
        case .steps(let value): metricsStore.steps = value
        }
    }

    func handle(_ event: Workout.Event) {
        // Only the controls follow pause events. The other screens read the session when
        // they close instead, so an event can't pull one out from under the user.
        switch state {
        case .running, .paused: break
        case .displayingPhoneConnection, .recordingRep, .ending: return
        }

        switch event {
        case .running: state = .running
        case .paused: state = .paused
        case .prepared, .stopped, .ended, .failed: break
        }
    }
}


// MARK: - Metrics store

extension Workout {
    enum Metrics {}
}

extension Workout.Metrics {
    @Observable
    final class Store {
        
        let maxHeartRate = 200.0
        
        private let workout: HKWorkoutSession
        
        /// Most recent heart reading. Nil until the first one arrives.
        fileprivate(set) var heartRate: Double?
        /// Totals so far. Start at zero.
        fileprivate(set) var activeEnergy: Double = 0
        fileprivate(set) var distance: Double = 0
        fileprivate(set) var steps: Double = 0
        
        
        init(workout: HKWorkoutSession) {
            self.workout = workout
        }
        
        func elapsedTime(at date: Date) -> TimeInterval {
            workout.associatedWorkoutBuilder().elapsedTime(at: date)
        }
    }
}


