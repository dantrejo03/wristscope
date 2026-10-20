//
//  ApplicationStore.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import Foundation
import HealthKit
import SwiftUI


@Observable
final class ApplicationStore {
    private(set) var state: State = .home(isStarting: false)

    // `HKWorkoutSession.delegate` is weak, so this is the only strong reference.
    @ObservationIgnored private let observer = Workout.Session.Observer()
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    
    let sensor = Motion.Sensor(deliveringOn: Motion.queue)
    let connectivity = WatchConnectivityManager.shared

    init() {
        setUpObservationTask()
    }

    deinit {
        observationTask?.cancel()
    }

    func start(_ workout: Workout.Kind) async {
        // Marked right away, so a second tap is ignored while Health is checked
        guard case .home(isStarting: false) = state else { return }
        state = .home(isStarting: true)

        do {
            if try await Workout.Manager.shared.needsAuthorization() {
                try await Workout.Manager.shared.requestAuthorization()
            }

            let session = try Workout.Manager.shared.prepare(
                workout.activityType, delegate: observer
            )
            let config = Workout.Store.Config(
                workout: session,
                kind: workout,
                sensor: sensor,
                connectivity: connectivity
            )
            let workoutStore = Workout.Store(config: config)
            
            state = .countdown(workoutStore, showLoading: false)
            
        } catch {
            state = .home(isStarting: false)
        }

        UserDefaults.standard.set(workout.rawValue, forKey: Workout.Kind.key)
    }

    func countdownEnded() {
        guard case .countdown(let store, _) = state else { return }
        
        guard store.workout.state == .prepared else {
            state = .countdown(store, showLoading: true)
            return
        }
        Task { await begin() }
    }

    private func begin() async {
        guard case .countdown(let store, _) = state else { return }
        
        do {
            try await Workout.Manager.shared.begin(store.workout)
            let _ = store.motionController.startSensors()
            state = .active(store)
        } catch {

        }
    }

    func dismissSummary() {
        guard case .summary = state else { return }
        state = .home(isStarting: false)
    }
}


extension ApplicationStore {
    enum State {
        /// `isStarting` while Health permission is checked and the session is prepared.
        case home(isStarting: Bool)
        case countdown(Workout.Store, showLoading: Bool)
        case active(Workout.Store)
        case summary(Workout.Summary)
    }
}


// MARK: - Observation

extension ApplicationStore {
    private func setUpObservationTask() {
        let events = observer.events
        observationTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: Workout.Event) {
        switch event {
        case .prepared:
            // The countdown already ended and is waiting on this
            if case .countdown(_, showLoading: true) = state {
                Task { await begin() }
            }
        case .running, .paused:
            // The session has only one delegate, so the workout store hears these through here
            if case .active(let store) = state {
                store.handle(event)
            }
        case .stopped(let date), .ended(let date):
            sessionFinished(at: date)
        case .failed:
            sessionFinished(at: .now)
        }
    }

    /// Every way the session can finish ends up here. Before the workout began, nothing is
    /// kept. After, whatever was collected is saved, and only End shows the summary.
    private func sessionFinished(at date: Date) {
        switch state {
        case .countdown(let store, _):
            store.discard()
            state = .home(isStarting: false)
        case .active(let store):
            Task {
                await store.finish(at: date)
                guard case .active = state else { return }
                if store.isEndRequested, let summary = store.summary {
                    state = .summary(summary)
                } else {
                    state = .home(isStarting: false)
                }
            }
        case .home, .summary:
            break
        }
    }
}
