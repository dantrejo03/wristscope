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
        enum Tab {
            case metrics, controls, nowPlaying
        }
        
        enum State {
            case running
            case paused
            case recordingRep(since: TimeInterval)
            case ending
        }
        
        var tabSelection: Tab = .controls

        /// Most recent reading. Nil until the first one arrives.
        private(set) var heartRate: Double?
        private(set) var activeEnergy: Double = 0
        private(set) var distance: Double = 0
        private(set) var steps: Double = 0

        /// Changed only by the session's `.paused` and `.running` events, never by the button.
        private(set) var isPaused = false

        @ObservationIgnored let session: HKWorkoutSession
        
        @ObservationIgnored let sessionType: SessionType

        // `HKLiveWorkoutBuilder.delegate` is weak, so this is the only strong reference.
        @ObservationIgnored private let builderObserver = Builder.Observer()

        @ObservationIgnored private var observationTask: Task<Void, Never>?

        init(session: HKWorkoutSession, type: SessionType) {
            self.session = session
            self.sessionType = type
            // Set before `beginCollection`, so no readings are missed
            session.associatedWorkoutBuilder().delegate = builderObserver
            setUpObservationTask()
        }

        deinit {
            observationTask?.cancel()
        }

        /// Only asks HealthKit. The button flips once the session reports the change.
        func togglePause() {
            if isPaused { session.resume() } else { session.pause() }
        }

        func end() {
            session.end()
        }

        /// The wildcard button's action, which depends on the session type saved in settings.
        func wildcardTapped() {
            switch sessionType {
            case .workout:
                // TODO: drop a marker at the current time
                break
            case .rep:
                // TODO: start or stop a rep
                break
            case .live:
                // TODO: show the phone connection status view
                break
            }
        }
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
        case .heartRate(let value): heartRate = value
        case .activeEnergy(let value): activeEnergy = value
        case .distance(let value): distance = value
        case .steps(let value): steps = value
        }
    }

    func handle(_ event: Workout.Event) {
        switch event {
        case .running: isPaused = false
        case .paused: isPaused = true
        case .prepared, .ended, .failed: break
        }
    }
}


